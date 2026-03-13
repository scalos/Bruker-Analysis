function [stats,figs] = epsiDiagnostics(epsiEx,opts)
    arguments
        epsiEx;
        opts.showPlots = false;
    end
    enum = sprintf('E%d',epsiEx.num);
    dataShape = epsiEx.sysParams.dataShape;
    dataShape = dataShape([2,1,3:end]);
    epsiRaw = reshape(epsiEx.rawData,dataShape);
    epsiRaw = permute(epsiRaw,[2,1,3,4,5]);
    epsiRaw_odd = epsiRaw(1:2:end,:,:,:,:);
    epsiOdd = DataRecon(epsiRaw_odd,"K","allParams",epsiEx.sysParams,'hzBW',epsiEx.sysParams.hzBW/2,'ppmBW',epsiEx.sysParams.ppmBW/2,'dataShape',size(epsiRaw_odd));
    epsiRaw_even = epsiRaw(2:2:end,:,:,:,:);
    epsiEven = DataRecon(flip(epsiRaw_even,2),"K","allParams",epsiEx.sysParams,'hzBW',epsiEx.sysParams.hzBW/2,'ppmBW',epsiEx.sysParams.ppmBW/2,'dataShape',size(epsiRaw_even));
    
    odd_yFit = polyfit(1:size(epsiOdd.kData,3),squeeze(mean(abs(epsiOdd.kData),[1,2,4,5])),1);
    even_yFit = polyfit(1:size(epsiEven.kData,3),squeeze(mean(abs(epsiEven.kData),[1,2,4,5])),1);

    odd_xFit = polyfit(1:size(epsiOdd.kData,2),squeeze(mean(abs(epsiOdd.kData),[1,3,4,5])),1);
    even_xFit = polyfit(1:size(epsiEven.kData,2),squeeze(mean(abs(epsiEven.kData),[1,3,4,5])),1);
    [odd_min,odd_max] = bounds(mean(abs(epsiOdd.rData),[1,4,5]),"all");
    odd_realRange = odd_max-odd_min;
    [even_min,even_max] = bounds(mean(abs(epsiEven.rData),[1,4,5]),"all");
    even_realRange = even_max-even_min;
    
    stats = struct('ky_std',[std(squeeze(mean(abs(epsiOdd.kData),[1,2,4,5]))),std(squeeze(mean(abs(epsiEven.kData),[1,2,4,5])))],...
                   'kx_std',[std(squeeze(mean(abs(epsiOdd.kData),[1,3,4,5]))),std(squeeze(mean(abs(epsiEven.kData),[1,3,4,5])))],...
                   'ky_slope',[odd_yFit(1),even_yFit(1)],...
                   'kx_slope',[odd_xFit(1),even_xFit(1)],...
                   'y_std',[std(squeeze(mean(abs(epsiOdd.rData),[1,2,4,5]))),std(squeeze(mean(abs(epsiEven.rData),[1,2,4,5])))],...
                   'x_std',[std(squeeze(mean(abs(epsiOdd.rData),[1,3,4,5]))),std(squeeze(mean(abs(epsiEven.rData),[1,3,4,5])))],...
                   'realRange',[odd_realRange,even_realRange]);

    if opts.showPlots
        figs = cell(1,2);
        for idx = 1:2
            figs{idx} = figure;
            if idx == 1
                set(gcf(),'Name',sprintf('%s Odd Echo Plots',enum));
                kData = epsiOdd.kData;
                rData = epsiOdd.rData;
            else
                set(gcf(),'Name',sprintf('%s Even Echo Plots',enum));
                kData = epsiEven.kData;
                rData = epsiEven.rData;
            end
            %k-space plot:
            imagesc(subplot(3,2,1),squeeze(mean(abs(kData),[1,4,5]))');
            title(gca(),'Collapsed k-space (mean(abs))')
            xlabel(gca(),'kx');
            ylabel(gca(),'ky');
        
            imagesc(subplot(3,2,2),squeeze(mean(abs(rData),[1,4,5]))');
            title(gca(),'Collapsed r-space (mean(abs))');
            xlabel(gca(),'x');
            ylabel(gca(),'y');
    
            plot(subplot(3,2,3),squeeze(mean(abs(kData),[1,2,4,5])));
            title(gca(),'Collapsed k-space rows (mean(abs))');
            xlabel(gca(),'ky');
            ylabel(gca(),'Mean(abs(signal)) a.u.');
    
            plot(subplot(3,2,4),squeeze(mean(abs(kData),[1,2,3,4])));
            title(gca(),'Collapsed k-space data (mean(abs))');
            xlabel(gca(),'Frames');
            ylabel(gca(),'Mean(abs(signal)) a.u.');
    
            plot(subplot(3,2,5),squeeze(mean(abs(kData),[1,3,4,5])));
            title(gca(),'Collapsed k-space columns (mean(abs))');
            xlabel(gca(),'kx');
            ylabel(gca(),'Mean(abs(signal)) a.u.');
    
            plot(subplot(3,2,6),squeeze(mean(abs(rData),[2,3,4,5])));
            title(gca(),'Collapsed r-space spectrum (mean(abs))');
            xlabel(gca(),'index');
            ylabel(gca(),'Mean(abs(signal)) a.u.');
        end
    end
end