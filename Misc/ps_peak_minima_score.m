function score = ps_peak_minima_score(ph, data, peakWidth)
    % Peak minima phase scoring function
    
    phc0 = ph(1);
    phc1 = ph(2);
    s0 = ps(data, phc0, 0, phc1);
    dataR = real(s0);
    
    [~, i] = max(dataR);
    i_start = max(1, i - peakWidth);
    i_end = min(length(dataR), i + peakWidth);
    
    mina = min(dataR(i_start:i));
    minb = min(dataR(i:i_end));
    
    score = abs(mina - minb);
end
