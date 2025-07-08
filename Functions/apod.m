function data = apod(data,lb,dt)
    arguments
        data;
        lb {mustBeNumeric};
        dt {mustBeNumeric,mustBeGreaterThan(dt,0)}
    end
    
    tp = (dt)*(1:length(data));
    lbf = exp(-lb*tp);
    data = (lbf'.*data);
end