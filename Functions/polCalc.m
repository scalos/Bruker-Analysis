function dynFit = polCalc(dynInts,tAx,teInt,flipAng,p0,tDelay,opts)
    %%%%%%%%%%%%%
    % polCalc(dynInts,tAx,teInt,flipAng,p0,tDelay,opts)
    %   dynInts: array of integrals from polarization decay spectra
    %       tAx: list of times in seconds corresponding to decay acquisition
    %     teInt: integral of thermal signal
    %   flipAng: flip angle used for the acquisition in deg
    %        p0: natural polarization (use natPol.m or calculate manually)
    %    tDelay: delay in seconds from dissol. to start of decay acquisition
    %   options: (Both default true)
    %         - opts.flipCorr: correct dnp according to flip angle 
    %        - opts.decayCorr: compensate for depletion of dnp signal from
    %                           measurements
    %
    % Returns a fit object corresponding to the decay fit and creates a
    % plot of the fit with % polarization and T1 labeled.
    %%%%%%%%%%%%%

    arguments
        dynInts 
        tAx
        teInt 
        flipAng {mustBeNumeric,mustBeGreaterThan(flipAng,0)};
        p0 
        tDelay 
        opts.flipCorr {mustBeNumericOrLogical} = true;
        opts.decayCorr {mustBeNumericOrLogical} = true;
    end
    dynInts = dynInts(:);
    tAx = tAx(:)+tDelay;
    if opts.flipCorr
		flipAngRad = deg2rad(flipAng);	
	    for idx = (1:length(dynInts))
            dynInts(idx) = dynInts(idx)/sin(flipAngRad);
            if opts.decayCorr
                if flipAng ~= 90
                    dynInts(idx) = dynInts(idx)/(cos(flipAngRad)^(idx-1));
                end
            end
        end
    end
    dynInts = dynInts.*(p0/teInt);
    dynFit = fit(tAx,dynInts,'exp1');
    T1 = -1/dynFit.b;
    pDissol = dynFit(0);
    ax = axes(figure);
    hold(ax,"on");
    scatter(ax,tAx,dynInts,20,DisplayName='     Data');
    fitAx = (0:tAx(2)-tAx(1):tAx(end));
    plot(ax,fitAx,dynFit(fitAx),'LineStyle','--',Color='black',DisplayName=sprintf('\n%s',formattedDisplayText(dynFit)));
    ylabel(ax,'Polarization (%)');
    xlabel(ax,'Time from Dissolution (s)');
    title(ax,'Polarization Decay');
    text(ax,2/3*mean(fitAx),pDissol*0.6,sprintf('Polarization at dissolution: %0.2f%%\nT1: %0.2f (s)',pDissol,T1));
    legend(ax);
    hold(ax,'off');
end