function score = entropyScore(data)
    % ACME entropy-based score assuming data is already phase corrected
    % data: real-valued vector (already phased real spectrum)

    % Ensure column vector
    data = real(data(:));
    stepsize = 1;

    % First derivative of the real signal
    ds1 = abs((data(2:end) - data(1:end-1)) / (2 * stepsize));

    % Normalize to form probability distribution
    p1 = ds1 / sum(ds1 + eps);

    % Entropy calculation
    p1(p1 == 0) = 1;  % log(1) = 0, avoids log(0)
    h1 = -p1 .* log(p1);
    h1s = sum(h1);

    % Penalty for negative values (non-physical in absorption spectrum)
    as_ = data - abs(data);
    if sum(as_) < 0
        pfun = sum((as_/2).^2);
    else
        pfun = 0;
    end

    % Final score (normalized)
    score = (h1s + 0 * pfun) / numel(data) / max(data + eps);
end