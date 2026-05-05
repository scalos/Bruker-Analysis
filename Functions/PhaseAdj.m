classdef PhaseAdj < handle
    properties
        ax;
        phi0_knob;
        phi1_knob;
        pivot_spinner;
        panel = gobjects(0);
        specData;
        specHandle = gobjects(0);
        pivotHandle = gobjects(0);
        ppmAx;
        hzAx;
        specAxSetting = 'ind';
        mode = 'real';
        pivot_unitLabel;
        phi0;
        phi1;
        pivot_ind;
        phi0_incBtn;
        phi0_decBtn;
        specAxDropdown;
        modeDropdown;
        applyPhaseButton;
        applyPhaseFun;
        phi1_incBtn;
        phi1_decBtn;
        resetPhasesBtn;
        tb;
        badFocus = 0;
        badFocAlert = gobjects(0);
    end

    properties (Dependent)
        specAx;
        currPhase;
    end


    methods

        function sAx = get.specAx(obj)
            indAx = 1:numel(obj.specData);
            switch obj.specAxSetting
                case 'ind'
                    sAx = indAx;
                case 'ppm'
                    if isempty(obj.ppmAx)
                        warning('Unable to use ppm axis, reverting to index.')
                        obj.specAxSetting = 'ind';
                        sAx = indAx;
                    else
                        sAx = obj.ppmAx;
                    end
                case 'hz'
                    if isempty(obj.hzAx)
                        warning('Unable to use hz axis, reverting to index.')
                        obj.specAxSetting = 'ind';
                        sAx = indAx;
                    else
                        sAx = obj.hzAx;
                    end
            end
        end

        function set.specAxSetting(obj,val)
            assert(ismember(val,{'ind','ppm','hz'}),'ERROR: invalid axes setting. Must be: "ind", "ppm", or "hz"');
            obj.specAxSetting = val;
            obj.updatePivotSpinner;
            obj.updatePlot("reframe",1);
        end

        function inds = ppm2ind(obj,vals)
            if isempty(obj.ppmAx)
                inds = [];
                return
            end
            inds = zeros(size(vals));
            for ind = 1:numel(vals)
                [~,idx] = min(abs(obj.ppmAx-vals(ind)));
                inds(ind) = idx;
            end
        end

        function inds = hz2ind(obj,vals)
            if isempty(obj.hzAx)
                inds = [];
                return
            end
            inds = zeros(size(vals));
            for ind = 1:numel(vals)
                [~,idx] = min(abs(obj.hzAx-vals(ind)));
                inds(ind) = idx;
            end
        end

        function phase = get.currPhase(obj)
            pivotInd = obj.pivot_ind;
            if isempty(obj.phi0)
                phase = repmat(obj.phi0,length(obj.specData),1);
            else
                phase = ((1:length(obj.specData))'-pivotInd)*obj.phi1+obj.phi0;
            end
        end

        function apivot = apparentPivot(obj)
            pivotInd = obj.pivot_ind;
            switch obj.specAxSetting
                case 'ind'
                    apivot = pivotInd;
                case 'ppm'
                    apivot = obj.ppmAx(pivotInd);
                case 'hz'
                    apivot = obj.hzAx(pivotInd);
            end

        end

        function updatePlot(obj,opts)
            arguments
                obj
                opts.reframe = false;
                opts.showPivot = true;
            end
            newSpecAx = obj.specAx;

            if obj.badFocus
                if isempty(obj.badFocAlert)||~isvalid(obj.badFocAlert)
                    cla(obj.ax);
                    xlim(obj.ax,[0,1]);
                    ylim(obj.ax,[0,1]);
                    obj.badFocAlert = text(obj.ax,0.5,0.5,'BAD FOCUS!','FontSize',50,...
                        'HorizontalAlignment','center','VerticalAlignment','middle');
                end
            else
                if all(isvalid(obj.badFocAlert))&&~all(isempty(obj.badFocAlert))
                    delete(obj.badFocAlert)
                end
                psData = obj.specData(:).*exp(1i*deg2rad(obj.currPhase(:)));
                switch obj.mode
                    case 'real'
                        newData = real(psData);
                    case 'imag'
                        newData = imag(psData);
                    case 'abs'
                        newData = abs(psData);
                end
                if ~all(isvalid(obj.specHandle))||all(isempty(obj.specHandle))
                    obj.specHandle = plot(obj.ax,newData);
                else
                    obj.specHandle.YData = newData;
                end
                obj.specHandle.XData = newSpecAx;
                if opts.showPivot
                    apivot = obj.apparentPivot;
                    if ~all(isvalid(obj.pivotHandle))||all(isempty(obj.pivotHandle))
                        obj.pivotHandle = xline(obj.ax,apivot,'--');
                    else
                        obj.pivotHandle.Value = apivot;
                    end
                end
                %plot setup:
                if opts.reframe
                    axis(obj.ax,'padded');
                end
                set(obj.ax,'XDir','reverse');
                switch obj.specAxSetting
                    case 'ind'
                        xlabel(obj.ax,'Frequency (index)');
                    case 'ppm'
                        xlabel(obj.ax,'Chemical Shift (ppm)');
                    case 'hz'
                        xlabel(obj.ax,'Frequency (hz)');
                end
                ylabel(obj.ax,'MR Signal (a.u.)');
            end
        end

        function knobChange(obj,src,~)
            switch src.Tag
                case 'phi0_knob'
                    obj.phi0 = src.Value;
                case 'phi1_knob'
                    obj.phi1 = src.Value;
            end
            obj.updatePlot;
        end

        function precisionButtons(obj,src,~)
            phi0_ticks = obj.phi0_knob.MinorTicks;
            phi0_precision = phi0_ticks(2)-phi0_ticks(1);
            phi1_ticks = obj.phi1_knob.MinorTicks;
            phi1_precision = phi1_ticks(2)-phi1_ticks(1);
            switch src.Tag
                case 'phi0_incBtn'
                    newPhi0Ticks = phi0_ticks(1):phi0_precision/10:phi0_ticks(end);
                    set(obj.phi0_knob,'MinorTicks',newPhi0Ticks);
                case 'phi0_decBtn'
                    newPhi0Ticks = phi0_ticks(1):phi0_precision*10:phi0_ticks(end);
                    set(obj.phi0_knob,'MinorTicks',newPhi0Ticks);
                case 'phi1_incBtn'
                    newPhi1Ticks = phi1_ticks(1):phi1_precision/10:phi1_ticks(end);
                    set(obj.phi1_knob,'MinorTicks',newPhi1Ticks);
                case 'phi1_decBtn'
                    newPhi1Ticks = phi1_ticks(1):phi1_precision*10:phi1_ticks(end);
                    set(obj.phi1_knob,'MinorTicks',newPhi1Ticks);
            end
        end

        function updatePivotSpinner(obj)
            pivotInd = obj.pivot_ind;
            
            switch obj.specAxSetting
                case 'ind'
                    val = pivotInd;
                    dx = 1;
                    [mn,mx] = bounds(1:numel(obj.specData));
                case 'ppm'
                    val = obj.ppmAx(pivotInd);
                    dx = obj.ppmAx(2)-obj.ppmAx(1);
                    [mn,mx] = bounds(obj.ppmAx);
                case 'hz'
                    val = obj.hzAx(pivotInd);
                    dx = obj.hzAx(2)-obj.hzAx(1);
                    [mn,mx] = bounds(obj.hzAx);
            end
            if isempty(mn)
                mn = 0;
            end
            if isempty(mx)
                mx = 1;
            end
            obj.pivot_spinner.Limits = [mn,mx];
            obj.pivot_spinner.Value = round(val,2);
            obj.pivot_spinner.Step = dx;
            obj.pivot_unitLabel.Text = obj.specAxSetting;
        end

        function pivotSpinnerChanged(obj,src,~)
            newVal = src.Value;
            switch obj.specAxSetting
                case 'ind'
                    obj.pivot_ind = newVal;
                case 'ppm'
                    obj.pivot_ind = obj.ppm2ind(newVal);
                case 'hz'
                    obj.pivot_ind = obj.hz2ind(newVal);
            end
            obj.updatePivotSpinner;
            obj.updatePlot;
        end
        
        function initGraphics(obj)
            if isempty(obj.panel)
                fig = uifigure;
                obj.panel = uipanel(fig);
                obj.panel.Units = 'normalized';
                obj.panel.Position = [0,0,1,1];
            end

            figGrid = uigridlayout(obj.panel,'ColumnWidth',{'3x','1x'},'RowHeight',{'2x','8x','1x'});
            optionsGrid = uigridlayout(figGrid,'ColumnWidth',{'1x','1x','1x','1x','1x','1x'},'RowHeight',{'1x','1x'});
            optionsGrid.Layout.Row = 1;
            optionsGrid.Layout.Column = [1,2];
            phiGrid = uigridlayout(figGrid,'ColumnWidth',{'1x','1x'},'RowHeight',{'3x','1x','3x','1x'});
            phiGrid.Layout.Row = [2,3];
            phiGrid.Layout.Column = 2;
            pivotGrid = uigridlayout(figGrid,'ColumnWidth',{'1x','1x','1x','1x'},'RowHeight',{'1x'});
            pivotGrid.Layout.Row = 3;
            pivotGrid.Layout.Column = 1;

            obj.ax = uiaxes(figGrid);
            obj.ax.Layout.Row = 2;
            obj.ax.Layout.Column = 1;


            obj.phi0_knob = uiknob(phiGrid,"Limits",[-180,180], ...
                                        "Value",obj.phi0, ...
                                        'ValueChangedFcn',@(src,evt) obj.knobChange(src,evt),...
                                        'Tag','phi0_knob');
            obj.phi0_knob.Layout.Row = 1;
            obj.phi0_knob.Layout.Column = [1,2];
            
            obj.phi0_incBtn = uibutton(phiGrid,'push','Text', ...
                                            '+', ...
                                            'tag', 'phi0_incBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi0_incBtn.Layout.Row = 2;
            obj.phi0_incBtn.Layout.Column = 2;

            obj.phi0_decBtn = uibutton(phiGrid,'push','Text', ...
                                            '-', ...
                                            'tag', 'phi0_decBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi0_decBtn.Layout.Row = 2;
            obj.phi0_decBtn.Layout.Column = 1;
            
            
            obj.phi1_knob = uiknob(phiGrid,"Limits",[-5,5], ...
                                        "Value",obj.phi1, ...
                                        'ValueChangedFcn',@(src,evt) obj.knobChange(src,evt),...
                                        'Tag','phi1_knob');
            obj.phi1_knob.Layout.Row = 3;
            obj.phi1_knob.Layout.Column = [1,2];
            
            
            obj.phi1_incBtn = uibutton(phiGrid,'push','Text', ...
                                            '+', ...
                                            'tag', 'phi1_incBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi1_incBtn.Layout.Row = 4;
            obj.phi1_incBtn.Layout.Column = 2;

            obj.phi1_decBtn = uibutton(phiGrid,'push','Text', ...
                                            '-', ...
                                            'tag', 'phi1_decBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi1_decBtn.Layout.Row = 4;
            obj.phi1_decBtn.Layout.Column = 1;
            

            pivot_label = uilabel(pivotGrid,'Text','Pivot:','HorizontalAlignment','right');
            pivot_label.Layout.Row = 1;
            pivot_label.Layout.Column = 1;
            obj.pivot_spinner = uispinner(pivotGrid,'ValueChangedFcn',@(src,evt) obj.pivotSpinnerChanged(src,evt));
            obj.pivot_spinner.Layout.Row = 1;
            obj.pivot_spinner.Layout.Column = 2;
            obj.pivot_unitLabel = uilabel(pivotGrid,'HorizontalAlignment','left');
            obj.pivot_unitLabel.Layout.Row = 1;
            obj.pivot_unitLabel.Layout.Column = 3;
            obj.updatePivotSpinner;
            

            
            obj.specAxDropdown = uidropdown(optionsGrid,'ValueChangedFcn',@(src,evt) obj.specDropdownChanged(src,evt));
            obj.specAxDropdown.Layout.Row = 2;
            obj.specAxDropdown.Layout.Column = 1;
            obj.setupSpecDropdown;
            specAxDropdownLbl = uilabel(optionsGrid,'Text','x axis','HorizontalAlignment','center');
            specAxDropdownLbl.Layout.Row = 1;
            specAxDropdownLbl.Layout.Column = 1;

            obj.modeDropdown = uidropdown(optionsGrid,...
                                          'ValueChangedFcn',@(src,evt) obj.modeDropdownChanged(src,evt),...
                                          'Value','real',...
                                          'Items',{'real','imag','abs'});
            obj.modeDropdown.Layout.Row = 2;
            obj.modeDropdown.Layout.Column = 2;
            modeDropdownLbl = uilabel(optionsGrid,'Text','mode','HorizontalAlignment','center');
            modeDropdownLbl.Layout.Row = 1;
            modeDropdownLbl.Layout.Column = 2;

            obj.applyPhaseButton = uibutton(optionsGrid, ...
                                            "ButtonPushedFcn",@obj.applyPhaseFun, ...
                                            "Text",'Apply Phase',...
                                            'VerticalAlignment','center',...
                                            'HorizontalAlignment','center');
            obj.applyPhaseButton.Layout.Row = 2;
            obj.applyPhaseButton.Layout.Column = 3;

            obj.resetPhasesBtn = uibutton(optionsGrid, ...
                                            "ButtonPushedFcn",@(~,~) obj.resetPhases, ...
                                            "Text",'Clear Phases',...
                                            'VerticalAlignment','center',...
                                            'HorizontalAlignment','center');
            obj.resetPhasesBtn.Layout.Row = 2;
            obj.resetPhasesBtn.Layout.Column = 6;
        end

        function updateGraphics(obj)
            obj.phi0_knob.Value = obj.phi0;
            obj.phi1_knob.Value = obj.phi1;
            obj.setupSpecDropdown;
            obj.updatePivotSpinner;
        end


        function resetPhases(obj)
            obj.phi0 = 0;
            obj.phi1 = 0;
            obj.pivot_ind = 1;
            obj.updatePlot;
            obj.updateGraphics;
        end

        function modeDropdownChanged(obj,src,~)
            obj.mode = src.Value;
            obj.updatePlot;
        end

        function specDropdownChanged(obj,src,~)
            obj.specAxSetting = src.Value;
        end

        function setupSpecDropdown(obj)
            items = {'ind'};
            if ~isempty(obj.ppmAx)
                items{end+1} = 'ppm';
            end
            if ~isempty(obj.hzAx)
                items{end+1} = 'hz';
            end
            obj.specAxDropdown.Items = items;
            obj.specAxDropdown.Value = obj.specAxSetting;
        end
    
        function obj = PhaseAdj(specData,opts)
            arguments
                specData (1,:) %1D spectral data (complex)
                opts.parent = [] %panel handle to embed phasing window
                opts.ppmAx = [];
                opts.hzAx = [];
                opts.applyPhaseFun function_handle = @()[];
                opts.phi0 double = [];
                opts.phi1 double = [];
                opts.pivot_ind double = [];
            end
            obj.applyPhaseFun = opts.applyPhaseFun;
            obj.specData = specData;
            obj.panel = opts.parent;
            obj.ppmAx = opts.ppmAx;
            phi0 = opts.phi0;
            if isempty(phi0)
                phi0 = 0;
            end
            obj.phi0 = phi0;

            phi1 = opts.phi1;
            if isempty(phi1)
                phi1 = 0;
            end
            obj.phi1 = phi1;

            pivot_ind = opts.pivot_ind;
            if isempty(pivot_ind)
                pivot_ind = 1;
            end
            obj.pivot_ind = pivot_ind;

            if ~isempty(obj.ppmAx)
                assert(isequal(numel(obj.ppmAx),numel(specData)),'ERROR: ppm axis values does not match number of spectral points');
            end            
            obj.hzAx = opts.hzAx;
            if ~isempty(obj.hzAx)
                assert(isequal(numel(obj.hzAx),numel(specData)),'ERROR: hz axis values does not match number of spectral points');
            end

        end 
    end
end