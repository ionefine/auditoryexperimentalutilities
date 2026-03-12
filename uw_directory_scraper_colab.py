import asyncio
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

import pandas as pd
from rapidfuzz import fuzz
from playwright.async_api import TimeoutError as PlaywrightTimeoutError
from playwright.async_api import async_playwright

# Colab-friendly defaults
INPUT_FILE = os.environ.get("UW_INPUT_FILE", "/content/UW_IPEDS_fiscal_staff_candidates.xlsx")
OUTPUT_FILE = os.environ.get("UW_OUTPUT_FILE", "/content/UW_fiscal_staff_with_departments.xlsx")
CHECKPOINT_FILE = os.environ.get("UW_CHECKPOINT_FILE", "/content/uw_directory_checkpoint.xlsx")
SAVE_EVERY = int(os.environ.get("UW_SAVE_EVERY", "1"))
HEADLESS = os.environ.get("UW_HEADLESS", "1") != "0"
DELAY_BETWEEN_SEARCHES_SEC = float(os.environ.get("UW_DELAY_SEC", "1.0"))

TITLE_HINTS = [
    "specialist", "analyst", "manager", "administrator", "director",
    "coordinator", "accountant", "controller", "officer", "assistant",
    "associate", "fiscal", "finance", "financial", "budget", "payroll",
    "procurement", "purchasing", "grants", "contracts", "treasury",
    "auditor", "buyer", "bursar", "tax",
]

DEPT_HINTS = [
    "department of", "office of", "school of", "college of", "division of",
    "program in", "center for", "centre for", "uw medicine", "finance",
    "financial", "budget", "payroll", "procurement", "purchasing",
    "grants", "contracts", "treasury", "business services",
    "administration", "controller", "tax", "bursar",
]

FISCAL_HINTS = [
    "finance", "financial", "budget", "payroll", "procurement",
    "purchasing", "grants", "contracts", "treasury", "account",
    "accounting", "controller", "tax", "bursar", "fiscal",
    "business services", "administration",
]


def in_colab() -> bool:
    return "google.colab" in sys.modules


def normalize(s: Optional[str]) -> str:
    if s is None:
        return ""
    s = str(s).strip()
    s = re.sub(r"\s+", " ", s)
    return s


def lowernorm(s: Optional[str]) -> str:
    return normalize(s).lower()


def token_overlap_score(a: str, b: str, min_len: int = 4) -> float:
    atoks = {t for t in re.split(r"\W+", lowernorm(a)) if len(t) >= min_len}
    btoks = {t for t in re.split(r"\W+", lowernorm(b)) if len(t) >= min_len}
    if not atoks or not btoks:
        return 0.0
    return float(len(atoks & btoks))


def is_likely_title(line: str) -> bool:
    s = lowernorm(line)
    return any(term in s for term in TITLE_HINTS)


def is_likely_department(line: str) -> bool:
    s = lowernorm(line)
    return any(term in s for term in DEPT_HINTS)


def looks_like_person_name(line: str) -> bool:
    s = normalize(line)
    if len(s) < 5 or len(s) > 60:
        return False

    bad_terms = [
        "search", "directory", "results", "department", "email", "phone",
        "office", "campus", "box", "seattle", "washington", "faculty/staff only",
        "sign in", "home", "maps", "libraries", "calendar", "privacy", "terms",
    ]
    if any(term in s.lower() for term in bad_terms):
        return False

    words = s.split()
    if not (2 <= len(words) <= 5):
        return False

    return bool(re.match(r"^[A-Z][A-Za-z'`\-.]+(?:\s+[A-Z][A-Za-z'`\-.]+){1,4}$", s))


def score_candidate(person_name: str, person_title: str, candidate: Dict[str, str]) -> float:
    score = 0.0

    cand_name = candidate.get("name", "")
    cand_title = candidate.get("title", "")
    cand_dept = candidate.get("department", "")
    cand_raw = candidate.get("raw", "")

    score += fuzz.ratio(lowernorm(person_name), lowernorm(cand_name)) / 15.0
    score += fuzz.partial_ratio(lowernorm(person_name), lowernorm(cand_name)) / 20.0

    name_parts = [p for p in re.split(r"\s+", lowernorm(person_name)) if p]
    if len(name_parts) >= 2:
        if name_parts[0] in lowernorm(cand_raw) and name_parts[-1] in lowernorm(cand_raw):
            score += 2.0

    if person_title and cand_title:
        score += fuzz.partial_ratio(lowernorm(person_title), lowernorm(cand_title)) / 25.0
        score += token_overlap_score(person_title, cand_title, min_len=4) * 1.2

    dept_and_title = f"{cand_dept} {cand_title}".lower()
    score += sum(0.3 for hint in FISCAL_HINTS if hint in dept_and_title)

    if not cand_title:
        score -= 0.5
    if not cand_dept:
        score -= 0.5

    return score


def parse_candidate_blocks_from_text(text: str) -> List[Dict[str, str]]:
    text = normalize(text)
    lines = [normalize(x) for x in text.splitlines()]
    lines = [x for x in lines if x]

    blocks: List[List[str]] = []
    current: List[str] = []
    for line in lines:
        if line.lower() in {"search", "uw directory", "search by", "search options", "kind of listing"}:
            continue
        current.append(line)
        if len(current) >= 6:
            blocks.append(current)
            current = []
    if current:
        blocks.append(current)

    candidates: List[Dict[str, str]] = []

    for i, line in enumerate(lines):
        if not looks_like_person_name(line):
            continue

        window = lines[max(0, i - 1): min(len(lines), i + 7)]
        name = line
        title = ""
        dept = ""

        for w in window:
            if not title and is_likely_title(w):
                title = w
            if not dept and is_likely_department(w):
                dept = w

        candidates.append({
            "name": name,
            "title": title,
            "department": dept,
            "raw": " | ".join(window),
        })

    for block in blocks:
        name = ""
        title = ""
        dept = ""
        for line in block:
            if not name and looks_like_person_name(line):
                name = line
            if not title and is_likely_title(line):
                title = line
            if not dept and is_likely_department(line):
                dept = line
        if name:
            candidates.append({
                "name": name,
                "title": title,
                "department": dept,
                "raw": " | ".join(block),
            })

    seen = set()
    deduped = []
    for c in candidates:
        key = (
            lowernorm(c.get("name")),
            lowernorm(c.get("title")),
            lowernorm(c.get("department")),
        )
        if key not in seen:
            seen.add(key)
            deduped.append(c)

    return deduped


def choose_best_candidate(person_name: str, person_title: str, candidates: List[Dict[str, str]]) -> Dict[str, str]:
    if not candidates:
        return {
            "DirectoryName": "",
            "DirectoryTitle": "",
            "Department": "",
            "BestScore": 0.0,
            "MatchStatus": "No candidate parsed",
            "CandidatePreview": "",
        }

    scored = []
    for c in candidates:
        score = score_candidate(person_name, person_title, c)
        scored.append((score, c))

    scored.sort(key=lambda x: x[0], reverse=True)
    best_score, best = scored[0]

    strong_count = sum(1 for score, _ in scored if score >= max(5.0, best_score - 1.0))
    if strong_count >= 2:
        status = "Ambiguous - multiple strong matches"
    elif best_score >= 8:
        status = "High-confidence match"
    elif best_score >= 5:
        status = "Probable match"
    elif best_score >= 3:
        status = "Low-confidence match"
    else:
        status = "Very low-confidence match"

    preview = " || ".join(
        f"[{score:.1f}] {c.get('name', '')} | {c.get('title', '')} | {c.get('department', '')}"
        for score, c in scored[:3]
    )

    return {
        "DirectoryName": best.get("name", ""),
        "DirectoryTitle": best.get("title", ""),
        "Department": best.get("department", ""),
        "BestScore": round(best_score, 2),
        "MatchStatus": status,
        "CandidatePreview": preview,
    }


def load_input() -> pd.DataFrame:
    path = Path(INPUT_FILE)
    if not path.exists():
        raise FileNotFoundError(f"Could not find {INPUT_FILE}")

    df = pd.read_excel(path)
    cols = {c.lower().strip(): c for c in df.columns}

    if "name" not in cols:
        raise ValueError('Input spreadsheet must include a "Name" column.')

    df = df.rename(columns={cols["name"]: "Name"})
    if "jobtitle" in cols:
        df = df.rename(columns={cols["jobtitle"]: "JobTitle"})
    elif "job title" in cols:
        df = df.rename(columns={cols["job title"]: "JobTitle"})
    else:
        df["JobTitle"] = ""

    for col in [
        "DirectoryName", "DirectoryTitle", "Department",
        "BestScore", "MatchStatus", "CandidatePreview", "SearchURL",
    ]:
        if col not in df.columns:
            df[col] = ""

    return df


def save_outputs(df: pd.DataFrame) -> None:
    review_mask = df["MatchStatus"].astype(str).str.contains(
        r"Low-confidence|Very low-confidence|Ambiguous|No candidate|Search failed|No visible result|Error",
        case=False, na=False,
    )
    summary = (
        df["MatchStatus"]
        .fillna("Missing")
        .astype(str)
        .value_counts(dropna=False)
        .rename_axis("MatchStatus")
        .reset_index(name="Count")
    )

    with pd.ExcelWriter(OUTPUT_FILE, engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name="All Results")
        df.loc[review_mask].to_excel(writer, index=False, sheet_name="Manual Review")
        summary.to_excel(writer, index=False, sheet_name="Summary")

    df.to_excel(CHECKPOINT_FILE, index=False)


async def try_set_faculty_staff_only(page) -> None:
    possible_labels = ["Faculty/Staff Only", "Faculty / Staff Only", "Faculty Staff Only"]
    for label in possible_labels:
        try:
            locator = page.get_by_label(label)
            if await locator.count() > 0:
                first = locator.first
                try:
                    if not await first.is_checked():
                        await first.check()
                except Exception:
                    await first.click()
                return
        except Exception:
            pass

    try:
        text_locator = page.get_by_text("Faculty/Staff Only", exact=False)
        if await text_locator.count() > 0:
            await text_locator.first.click()
    except Exception:
        pass


async def perform_search(page, person_name: str) -> str:
    await page.goto("https://directory.uw.edu/", wait_until="domcontentloaded", timeout=30000)
    await page.wait_for_timeout(1200)
    await try_set_faculty_staff_only(page)

    search_candidates = [
        'input[name="q"]',
        'input[type="search"]',
        'input[aria-label*="Search"]',
        'input[type="text"]',
    ]

    search_box = None
    for sel in search_candidates:
        locator = page.locator(sel)
        if await locator.count() > 0:
            search_box = locator.first
            break

    if search_box is None:
        raise RuntimeError("Could not find a search input on the UW directory page.")

    await search_box.click()
    await search_box.fill(person_name)
    await search_box.press("Enter")
    await page.wait_for_timeout(2200)

    return await page.locator("body").inner_text(timeout=10000)


def ensure_playwright_browsers() -> None:
    if shutil.which("playwright") is None:
        raise RuntimeError(
            "Playwright CLI is not installed. In Colab run: !pip install playwright"
        )

    try:
        subprocess.run(["playwright", "install", "chromium"], check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "Failed to install Chromium for Playwright. In Colab try: "
            "!playwright install --with-deps chromium"
        ) from exc


async def scrape_directory() -> None:
    df = load_input()

    if Path(CHECKPOINT_FILE).exists():
        ck = pd.read_excel(CHECKPOINT_FILE)
        if len(ck) == len(df) and "MatchStatus" in ck.columns:
            df = ck

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=HEADLESS)
        context = await browser.new_context()
        page = await context.new_page()

        try:
            for idx, row in df.iterrows():
                if str(row.get("MatchStatus", "")).strip():
                    continue

                person_name = normalize(row.get("Name"))
                person_title = normalize(row.get("JobTitle"))

                if not person_name:
                    df.at[idx, "MatchStatus"] = "Missing name"
                    continue

                print(f"{idx + 1}/{len(df)} {person_name}")

                try:
                    page_text = await perform_search(page, person_name)
                    df.at[idx, "SearchURL"] = "https://directory.uw.edu/"

                    if not normalize(page_text):
                        df.at[idx, "MatchStatus"] = "No visible result text"
                    else:
                        candidates = parse_candidate_blocks_from_text(page_text)
                        result = choose_best_candidate(person_name, person_title, candidates)
                        for k, v in result.items():
                            df.at[idx, k] = v

                except PlaywrightTimeoutError:
                    df.at[idx, "MatchStatus"] = "Search failed - timeout"
                except Exception as e:
                    df.at[idx, "MatchStatus"] = f"Error: {str(e)[:200]}"

                if (idx + 1) % SAVE_EVERY == 0:
                    save_outputs(df)
                    print(f"Saved progress at row {idx + 1}")

                await asyncio.sleep(DELAY_BETWEEN_SEARCHES_SEC)

        finally:
            save_outputs(df)
            await context.close()
            await browser.close()


async def run_scraper() -> None:
    await scrape_directory()


def run() -> None:
    """Notebook-safe entrypoint for Colab/Jupyter and CLI usage."""
    ensure_playwright_browsers()

    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if loop and loop.is_running():
        # For notebooks (incl. Colab) that already have an active event loop.
        import nest_asyncio

        nest_asyncio.apply()
        loop.run_until_complete(run_scraper())
    else:
        asyncio.run(run_scraper())


if __name__ == "__main__":
    if in_colab():
        print("Detected Colab environment. Running in headless mode.")
    run()
