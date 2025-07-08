function [psData,p0,p1,pivot] = autoPhase(data)
    arguments
        data (:,1) %Complex spectral data
    end
    data = smoothdata(data(:)); % ensure column vector
    [pks,locs,w,p] = findpeaks(abs(data));
    [~,inds] = sort(p,"descend");
    locsSorted = locs(inds);
    pksSorted = pks(inds);
    wSorted = w(inds);
    phases = rad2deg(unwrap(angle(data(inds))));
    p0Guess = -phases(1);
    pivot = locsSorted(1);
    p0 = fminsearch(@(p0)symScore(real(ps(data,p0)),pivot,wSorted(1)),p0Guess);
    
    phi1Range = (-5:0.1:5);
    peakInds = 2:10;
    weights = exp(-1*(0:length(peakInds)-1));
    %weights = pksSorted;
    H = zeros(size(phi1Range));
    figure;
    plot(subplot(1,2,1),real(ps(data,p0)));
    for idx = (1:length(phi1Range))
        phi1 = phi1Range(idx);
        for ind = (1:length(peakInds))
            m = peakInds(ind);
            ang = phases(m)+p0+phi1*(locsSorted(m)-locsSorted(1));
            score = abs(sind(ang)-1)/2;
            H(idx) = H(idx)+weights(ind)*score;
        end
        H(idx) = H(idx)/sum(weights);
        plot(subplot(1,2,1),real(ps(data,p0,pivot,phi1)));
        for ii = peakInds
            xline(subplot(1,2,1),locsSorted(ii));
        end
        plot(subplot(1,2,2),phi1Range(1:idx),H(1:idx));
        drawnow;
        pause(0.1)
    end
    [~,p1Ind] = min(H);
    p1 = phi1Range(p1Ind);
    disp(p1)


    % p1 = fminsearch(@(p1) sum(weights(2:end)'.*cosd(phases(2:end)+p0+p1*(locsSorted(2:end)-locsSorted(1)))),-3);

    % p1 = fminbnd(@(p1) sum(weights(2:end)'.*cosd(phases(2:end)+p0+p1*(locsSorted(2:end)-locsSorted(1)))),-4,);
    psData = ps(data,p0,pivot,p1);
    plot(axes(figure),real(psData))
end



% function [psData,p0,p1,pivot] = autoPhase(data)
%     arguments
%         data (:,1) %Complex spectral data
%     end
%     data = data(:); % ensure column vector
%     [pks,locs,w,p] = findpeaks(abs(data));
%     [~,inds] = sort(p,"descend");
%     locsSorted = locs(inds);
%     pksSorted = pks(inds);
%     wSorted = w(inds);
%     phases = rad2deg(unwrap(angle(data(inds))));
%     p0Guess = -phases(1);
%     pivot = locsSorted(1);
%     p0 = fminsearch(@(p0)symScore(real(ps(data,p0)),pivot,wSorted(1)),p0Guess);
%     phi1Range = (-5:0.1:5);
%     score = zeros(size(phi1Range));
%     baseTimes = zeros(size(phi1Range));
%     ax1 = subplot(2,2,1);
%     lam = (numel(data)/mean(3*wSorted(1:10)))^2;
%     for idx = (1:length(phi1Range))
%         phi1 = phi1Range(idx);
%         dataps = ps(data,p0,pivot,phi1);
%         tic;
%         [~,lower] = envelope(real(dataps),10*ceil(mean(wSorted(1:10))),'peak');
%         base = lower;
%         baseTimes(idx) = toc;
%         residual = sum(abs(real(dataps)-real(base)));
%         plot(ax1,real(dataps));
%         hold(ax1,'on');
%         plot(ax1,real(lower));
%         hold(ax1,'off');
%         %pause(.25);
%         score(idx) = residual;
%         plot(subplot(2,2,2),abs(real(dataps)-real(base)));
%         plot(subplot(2,2,[3,4]),phi1Range(1:idx),score(1:idx));
%         drawnow;
%     end
%     [~,p1Ind] = min(score);
%     p1 = phi1Range(p1Ind);
%     psData = ps(data,p0,pivot,p1);
%     ax = axes(figure);
%     plot(ax,real(psData));
%     hold(ax,"on");
%     disp(mean(baseTimes));
% end
