stats = {'ky_std','kx_std','ky_slope','kx_slope','y_std','x_std','realRange'};

allStats = cell2struct(cell(numel(stats),1),stats);
for idx = 1:numel(epsiInds)
    eInd = epsiInds(idx);
    epsiStats = epsiDiagnostics(study.getExpmt(eInd),"showPlots",true);
    fields = fieldnames(epsiStats);
    for fInd = 1:numel(fields)
        field = fields{fInd};
        if isfield(allStats,field)
            val = epsiStats.(field);
            allStats.(field) = cat(1,val,allStats.(field));
        end
    end
end

bandStatInd = 7;
bandStat = stats{bandStatInd};
bandStatData = allStats.(bandStat);
% for idx = 1:numel(stats)
%     if idx~=bandStatInd
%         stat = stats{idx};
%         statData = allStats.(stat);
%         corrOdd = corrcoef(statData(:,1),bandStatData(:,1));
%         corrEven = corrcoef(statData(:,2),bandStatData(:,2));
%         corrs = [corrOdd(1,2),corrEven(1,2)];
%         corrMax = max(corrs);
%         fprintf('Max correl between %s and %s is %f0.2\n',stat,bandStat,corrMax);
%         figure
%         for echo = 1:2
%             p = polyfit(bandStatData(:,echo),statData(:,echo),1);
%             plot(subplot(2,1,echo),bandStatData(:,echo),statData(:,echo),'o', ...
%                 bandStatData(:,echo),polyval(p,bandStatData(:,echo)),'-');
%             if echo == 1
%                 title(sprintf('Odd Echo %s vs %s',stat,bandStat),'Interpreter', 'none')
%             else
%                 title(sprintf('Even Echo %s vs %s',stat,bandStat),'Interpreter', 'none')
%             end
%             subtitle(sprintf('corr. fac: %f0.2',corrs(echo)));
%         end
%     end
% end
% 
% 
% 
