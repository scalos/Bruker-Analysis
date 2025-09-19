function psData = autoPS(data)
    function score = acmeScore(x)
        realPart = real(x);
        dR = diff(realPart);                       % Derivative
        weight = log(eps + abs(realPart(1:end-1)));
        score = -sum(dR .* weight);               % Negative for minimization
    end



    %start by identifying most prominent peak:
    [~,locs,ws,proms] = findpeaks(abs(data));
    [~,inds] = sort(proms,"descend");
    locs = locs(inds);
    ws = (inds);
    proms = proms(inds);
    %zeroth order phase using symmetric scoring around locs(1):
    p0Guess = -rad2deg(unwrap(angle(data(locs(1)))));
    options = optimset('MaxFunEvals',500*numel(data), ...
                       'MaxIter',500*numel(data),...
                       'TolFun',1e-5,...
                       'TolX',1e-5);
    [p0,~,exitType] = fminsearch(@(p0)symScore(real(ps(data,p0)),locs(1),100*ws(1)),p0Guess,options);
    fun = @(p) 1/acmeScore(ps(data(:), p(1), locs(1),p(2)));
    scores = []
    for p1 = -10:0.1:10
        
        scores(end+1) = 1/acmeScore(ps(data(:),p0,locs(1),p1));
    end

    
    
    
    bestParams = fminsearch(fun, [p0, 0],options);  % Or use other optimizers
    plot(axes(figure),real(ps(data,bestParams(1),locs(1),bestParams(2))));
end