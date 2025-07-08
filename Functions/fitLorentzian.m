function [fitresult, gof] = fitLorentzian(y,type,bds,opts)
    arguments
        y
        type {mustBeMember(type,{'singlet','doublet','triplet'})};
        bds (2,1) {mustBeInteger}
        opts.visualize {mustBeNumericOrLogical} = false;
    end
    y(1:min(bds)) = 0;
    y(max(bds):end) = 1;
    switch type
        case 'singlet'
            % Initial gamma guess (use span of bds / 10 as a default)
            gamma_guess = (max(bds) - min(bds)) / 10;
        
            % fix amp to max in bds, x0 guess is idx of max pt
            [amp_guess,x0_guess] = max(y);
        
            % Define Lorentzian with A as a fixed (problem) parameter
            lorentzian = fittype(@(x0, gamma, A, x) A ./ (1 + ((x - x0) ./ gamma).^2), ...
                'independent', 'x', 'coefficients', {'x0', 'gamma','A'});
        
            % Fit options
            fitOpts = fitoptions(lorentzian);
            fitOpts.StartPoint = [x0_guess, gamma_guess,amp_guess];
            fitOpts.Lower = [1, 0,0]; % gamma must be > 0
            x = (1:length(y))';
            % Fit the data
            [fitresult, gof] = fit(x, y, lorentzian, fitOpts);
        case 'doublet'
            % Initial gamma guess (use span of bds / 10 as a default)
            gamma_guess = (max(bds) - min(bds)) / 20;
        
            [amps,locs,~,~] = findpeaks(y,'NPeaks',2,'SortStr','descend');
            [~,inds] = sort(locs,"descend");
            locs = locs(inds);
            amps = amps(inds);
        
            % Define Lorentzian with A as a fixed (problem) parameter
            lorentzian = fittype(@(x1,x2, gamma1,gamma2, A1,A2, x) A1 ./ (1 + ((x - x1) ./ gamma1).^2)+...
                                                           A2 ./ (1 + ((x - x2) ./ gamma2).^2), ...
                'independent', 'x', 'coefficients', {'x1', 'x2','gamma1','gamma2','A1','A2'});
        
            % Fit options
            fitOpts = fitoptions(lorentzian);
            fitOpts.StartPoint = [locs(1),locs(2), gamma_guess,gamma_guess,amps(1),amps(2)];
            fitOpts.Lower = [1,1,0,0,0,0]; % gamma must be > 0
            x = (1:length(y))';
            % Fit the data
            [fitresult, gof] = fit(x, y, lorentzian, fitOpts);

         case 'triplet'
            % Initial gamma guess (use span of bds / 10 as a default)
            gamma_guess = (max(bds) - min(bds)) / 30;
        
            [amps,locs,~,~] = findpeaks(y,'NPeaks',3,'SortStr','descend');
            [~,inds] = sort(locs,"descend");
            locs = locs(inds);
            amps = amps(inds);
            % Define Lorentzian with A as a fixed (problem) parameter
            lorentzian = fittype(@(x1,x2,x3, gamma1,gamma2,gamma3, A1,A2,A3, x)...
                                A1 ./ (1 + ((x - x1) ./ gamma1).^2)+...
                                A2 ./ (1 + ((x - x2) ./ gamma2).^2)+ ...
                                A3 ./ (1 + ((x - x3) ./ gamma3).^2), ...
                'independent', 'x', 'coefficients', {'x1','x2','x3','gamma1','gamma2','gamma3','A1','A2','A3'});
        
            % Fit options
            fitOpts = fitoptions(lorentzian);
            fitOpts.StartPoint = [locs(1),locs(2),locs(3), gamma_guess,gamma_guess,gamma_guess,amps(1),amps(2),amps(3)];
            fitOpts.Lower = [1,1,1,0,0,0,0,0,0]; % gamma must be > 0
            x = (1:length(y))';
            % Fit the data
            [fitresult, gof] = fit(x, y, lorentzian, fitOpts);
            
    end

    % Optional: visualize
    
    if opts.visualize
        figure;
        plot(x, y, 'b.', 'DisplayName', 'Data');
        hold on;
        plot(x, fitresult(x), 'r-', 'LineWidth', 2, 'DisplayName', 'Fit');
        xlim([min(bds),max(bds)]);
        legend show;
        xlabel('x'); ylabel('y');
        title(sprintf('Lorentzian Fit (%s)',type));
    end
end
