function x = taper(x,frac)
len = round(length(x) * frac);
x(1:len) = x(1:len) .* (0.5 - 0.5*cos([1:len]*pi/len));
x(end-len+1:end) = x(end-len+1:end) .* (0.5+0.5*cos([1:len]*pi/len));