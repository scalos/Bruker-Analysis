function score = ps_acme_score(ph, data)
    % ACME phase scoring function
    
    phc0 = ph(1);
    phc1 = ph(2);
    s0 = ps(data, phc0, 0, phc1);
    dataR = real(s0);
    
    % First derivative
    ds1 = abs(diff(dataR));
    p1 = ds1 / sum(ds1);
    
    % Replace zeros with ones (for log)
    p1(p1 == 0) = 1;
    
    % Entropy
    h1 = -p1 .* log(p1);
    h1s = sum(h1);
    
    % Penalty for negative absorption
    as = dataR - abs(dataR);
    sumas = sum(as);
    
    pfun = 0;
    if sumas < 0
        pfun = sum((as / 2).^2);
    end
    
    penalty = 1000 * pfun;
    
    score = (h1s + penalty) / length(dataR) / max(dataR);
end
