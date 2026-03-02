function y = Normal(p,x)
%y = Weibull(p,x)
%
%Parameters:  p.b slope
%             p.t threshold yeilding ~80% correct
%             x   intensity values.


y = normcdf(x,p.t,p.b);

