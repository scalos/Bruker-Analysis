classdef BrukerAnalysis < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure             matlab.ui.Figure
        LoadMenu             matlab.ui.container.Menu
        StudyMenu            matlab.ui.container.Menu
        ProcessingMenu       matlab.ui.container.Menu
        BlankingMenu         matlab.ui.container.Menu
        LineBroadeningMenu   matlab.ui.container.Menu
        ZeroFillMenu         matlab.ui.container.Menu
        AnalysisMenu         matlab.ui.container.Menu
        RevertProcessingMenu matlab.ui.container.Menu
        IntegratePeaksMenu   matlab.ui.container.Menu
        ExperimentLabel      matlab.ui.control.Label
        ChannelDropDown      matlab.ui.control.DropDown
        ImaginaryCheckBox    matlab.ui.control.CheckBox
        RealCheckBox         matlab.ui.control.CheckBox
        AbsoluteCheckBox     matlab.ui.control.CheckBox
        ChannelLabel         matlab.ui.control.Label
        ViewModeButtonGroup  matlab.ui.container.ButtonGroup
        StackedButton        matlab.ui.control.RadioButton
        AverageButton        matlab.ui.control.RadioButton
        FirstinRangeButton   matlab.ui.control.RadioButton
        PivotSpinner         matlab.ui.control.Spinner
        PivotSpinnerLabel    matlab.ui.control.Label
        ScansSlider          matlab.ui.control.RangeSlider
        Phi1Spinner          matlab.ui.control.Spinner
        Phi1SpinnerLabel     matlab.ui.control.Label
        Phi0Spinner          matlab.ui.control.Spinner
        Phi0SpinnerLabel     matlab.ui.control.Label
        ScansSliderLabel     matlab.ui.control.Label
        Tree                 matlab.ui.container.Tree
        StudyNode            matlab.ui.container.TreeNode
        Expmt1Node           matlab.ui.container.TreeNode
        Expmt2Node           matlab.ui.container.TreeNode
        UIAxes2              matlab.ui.control.UIAxes
        UIAxes               matlab.ui.control.UIAxes
    end

    properties 
        StudyPath
        study
        currExpmt
        expmtReps = 1
        showAvg = false
        
    end


    % Callbacks that handle component events
    methods (Access = private)
        function update(app)
            app.updateViewReps;
            app.updateFID;
            app.updateSpec;
        end

        function updateViewReps(app)
            if length(app.expmtReps)>1
                repsBds = app.ScansSlider.Value;
                app.expmtReps = (repsBds(1):repsBds(2));
            end
        end
        function updateFID(app)
            expmtFIDs = app.currExpmt.fids();
            cla(app.UIAxes);
            hold(app.UIAxes,'on');
            if app.AbsoluteCheckBox.Value
                if app.showAvg
                plot(app.UIAxes,abs(mean(expmtFIDs(:,app.expmtReps),2)) ...
                    /max(abs(mean(expmtFIDs(:,app.expmtReps),2))),'color','black');
                else
                    plot(app.UIAxes,abs(expmtFIDs(:,app.expmtReps(1))) ...
                        /max(abs(expmtFIDs(:,app.expmtReps(1)))),'color','black');
                end
            end
            if app.RealCheckBox.Value
                if app.showAvg
                plot(app.UIAxes,real(mean(expmtFIDs(:,app.expmtReps),2)) ...
                    /max(real(mean(expmtFIDs(:,app.expmtReps),2))),'color','blue');
                else
                    plot(app.UIAxes,real(expmtFIDs(:,app.expmtReps(1))) ...
                        /max(real(expmtFIDs(:,app.expmtReps(1)))),'color','blue');
                end
            end
            if app.ImaginaryCheckBox.Value
                if app.showAvg
                plot(app.UIAxes,imag(mean(expmtFIDs(:,app.expmtReps),2)) ...
                    /max(imag(mean(expmtFIDs(:,app.expmtReps),2))),'color','red');
                else
                    plot(app.UIAxes,imag(expmtFIDs(:,app.expmtReps(1))) ...
                        /max(imag(expmtFIDs(:,app.expmtReps(1)))),'color','red');
                end
            end
            ylim(app.UIAxes,[-1.1,1.1]);
            hold(app.UIAxes,'off');
        end
        function updateSpec(app)
            expmtSpecs = app.currExpmt.specs();
            cla(app.UIAxes2);
            hold(app.UIAxes2,'on');
            if app.AbsoluteCheckBox.Value
                if app.showAvg
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        abs(mean(expmtSpecs(:,app.expmtReps),2))/ ...
                        max(abs(mean(expmtSpecs(:,app.expmtReps),2))),'color','black');
                else
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        abs(expmtSpecs(:,app.expmtReps(1)))/ ...
                        max(abs(expmtSpecs(:,app.expmtReps(1)))),'color','black');
                end
            end
            if app.RealCheckBox.Value
                if app.showAvg
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        real(mean(expmtSpecs(:,app.expmtReps),2))/ ...
                        max(real(mean(expmtSpecs(:,app.expmtReps),2))),'color','blue');
                else
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        real(expmtSpecs(:,app.expmtReps(1)))/ ...
                        max(real(expmtSpecs(:,app.expmtReps(1)))),'color','blue');
                end
            end
            if app.ImaginaryCheckBox.Value
                if app.showAvg
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        imag(mean(expmtSpecs(:,app.expmtReps),2))/ ...
                        max(imag(mean(expmtSpecs(:,app.expmtReps),2))),'color','red');
                else
                    plot(app.UIAxes2,app.currExpmt.xppm, ...
                        imag(expmtSpecs(:,app.expmtReps(1)))/ ...
                        max(imag(expmtSpecs(:,app.expmtReps(1)))),'color','red');
                end
            end
            set(app.UIAxes2,'xdir','reverse');
            ylim(app.UIAxes2,[-1.1,1.1]);
            hold(app.UIAxes,'off');

        end

        % Menu selected function: StudyMenu
        function loadStudy(app, ~)
            app.StudyPath = uigetdir;
            if ~app.StudyPath==0
                studyNode = uitreenode(app.Tree);
                studyNode.Text = "Loading...";
                figure(app.UIFigure);
                app.study = Study(app.StudyPath);
                for i = (1:length(app.study.expmts))
                    node = uitreenode(studyNode);
                    expmt = app.study.expmts(i);
                    node.Text = sprintf("(%s) %s",expmt.expmtNum,...
                    expmt.brukerObj.Acqp.ACQ_scan_name);
                end
                studyNode.Text = app.study.name{1};
            end
        end

        function selectExpmt(app,event)
            node = event.InteractionInformation.Node;
            expmtNum = regexp(node.Text,'[^()]*','match','once');
            for i = (1:length(app.study.expmts))
                expmt = app.study.expmts(i);
                if expmt.expmtNum == expmtNum
                    app.currExpmt = expmt;
                end
            end
            app.Phi0Spinner.Value = app.currExpmt.phasing(1);
            app.Phi1Spinner.Value = app.currExpmt.phasing(2);
            app.PivotSpinner.Value = app.currExpmt.phasePivot;
            app.ScansSlider.Limits = [1,app.currExpmt.nReps];
            app.update;
        end

        function applyProcessing(app,event)
            switch event.Source.Tag
                case "blank"
                    app.currExpmt.blank;
                case "lb"
                    lbFactor = inputdlg("Exponential Line Broadening Factor (Hz):");
                    figure(app.UIFigure);
                    app.currExpmt.lbExp(str2double(lbFactor{1}));
                case "zf"
                    zfFactor = inputdlg("Zero Fill Factor:");
                    figure(app.UIFigure);
                    app.currExpmt.zf(str2double(zfFactor{1}));
                case "revert"
                    selection = uiconfirm(app.UIFigure,"Revert processing on this data set?","Revert Data");
                    switch selection
                        case 'OK'
                            app.currExpmt.revertData;
                    end
            end
            app.update;
        end
        
        function applyViewPrefs(app,event)
            switch event.Source.Tag
                case 'viewMode'
                    switch event.NewValue.Tag
                        case 'viewAvg'
                            app.showAvg = true;
                        case 'viewFirst'
                            app.showAvg = false;
                    end
                case 'scanSlider'
                    repsBds = app.ScansSlider.Value;
                    app.expmtReps = (repsBds(1):repsBds(2));
                case 'abs/real/imag'
                    app.update;
            end
            app.update;
        end

        function applyAnalysis(app,event)
            switch event.Source.Tag
                case 'intPeaks'
                    bds = inputdlg({'Integration start (ppm):', ...
                        'Integration end (ppm)'},'Integrate Peaks');
                    bdsArr = [str2double(bds{1}),str2double(bds{2})];
                    specs = app.currExpmt.specs();
                    specs = specs(:,app.expmtReps);
                    if app.showAvg
                        specs = mean(specs,2);
                    end
                    ints = app.currExpmt.peakInts(specs,bdsArr);
                    disp(ints);
            end
        end

        function handlePhase(app,~)
            phi0 = app.Phi0Spinner.Value;
            phi1 = app.Phi1Spinner.Value;
            app.currExpmt.phasePivot = app.PivotSpinner.Value;
            app.currExpmt.phasing = [phi0,phi1];
            app.update;
        end
    
    end

    % Component initialization
    methods (Access = private)
       

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 736 466];
            app.UIFigure.Name = 'Bruker Analysis';

            % Create LoadMenu
            app.LoadMenu = uimenu(app.UIFigure);
            app.LoadMenu.Text = 'Load';

            % Create StudyMenu
            app.StudyMenu = uimenu(app.LoadMenu);
            app.StudyMenu.MenuSelectedFcn = createCallbackFcn(app, @loadStudy, true);
            app.StudyMenu.Text = 'Study';

            % Create ProcessingMenu
            app.ProcessingMenu = uimenu(app.UIFigure);
            app.ProcessingMenu.Text = 'Processing';

            % Create BlankingMenu
            app.BlankingMenu = uimenu(app.ProcessingMenu);
            app.BlankingMenu.MenuSelectedFcn = createCallbackFcn(app,@applyProcessing,true);
            app.BlankingMenu.Tag = "blank";
            app.BlankingMenu.Text = 'Blanking';

            % Create LineBroadeningMenu
            app.LineBroadeningMenu = uimenu(app.ProcessingMenu);
            app.LineBroadeningMenu.MenuSelectedFcn = createCallbackFcn(app,@applyProcessing,true);
            app.LineBroadeningMenu.Tag = "lb";
            app.LineBroadeningMenu.Text = 'Line Broadening';

            % Create ZeroFillMenu
            app.ZeroFillMenu = uimenu(app.ProcessingMenu);
            app.ZeroFillMenu.MenuSelectedFcn = createCallbackFcn(app,@applyProcessing,true);
            app.ZeroFillMenu.Tag = "zf";
            app.ZeroFillMenu.Text = 'Zero Fill';

            app.RevertProcessingMenu = uimenu(app.ProcessingMenu);
            app.RevertProcessingMenu.MenuSelectedFcn = createCallbackFcn(app,@applyProcessing,true);
            app.RevertProcessingMenu.Tag = "revert";
            app.RevertProcessingMenu.Text = "Undo all Processing";

            % Create AnalysisMenu
            app.AnalysisMenu = uimenu(app.UIFigure);
            app.AnalysisMenu.Text = 'Analysis';

            % Create IntegratePeaksMenu
            app.IntegratePeaksMenu = uimenu(app.AnalysisMenu);
            app.IntegratePeaksMenu.MenuSelectedFcn = createCallbackFcn(app,@applyAnalysis,true);
            app.IntegratePeaksMenu.Tag = 'intPeaks';
            app.IntegratePeaksMenu.Text = 'Integrate Peaks';

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, 'FID')
            xlabel(app.UIAxes, 'Time')
            ylabel(app.UIAxes, 'Normalized Signal')
            app.UIAxes.Position = [407 240 300 185];

            % Create UIAxes2
            app.UIAxes2 = uiaxes(app.UIFigure);
            title(app.UIAxes2, 'Spectrum')
            xlabel(app.UIAxes2, 'ppm')
            ylabel(app.UIAxes2, 'Normalized Signal')
            app.UIAxes2.Position = [407 47 300 185];

            % Create Tree
            app.Tree = uitree(app.UIFigure);
            app.Tree.Position = [1 142 150 300];
            app.Tree.DoubleClickedFcn = createCallbackFcn(app, @selectExpmt, true);
            
            % Create ScansSliderLabel
            app.ScansSliderLabel = uilabel(app.UIFigure);
            app.ScansSliderLabel.HorizontalAlignment = 'right';
            app.ScansSliderLabel.FontWeight = 'bold';
            app.ScansSliderLabel.Position = [232 316 40 22];
            app.ScansSliderLabel.Text = 'Scans';

            % Create ScansSlider
            app.ScansSlider = uislider(app.UIFigure, 'range');
            app.ScansSlider.ValueChangedFcn = createCallbackFcn(app,@applyViewPrefs,true);
            app.ScansSlider.Step = 1;
            app.ScansSlider.Tag = 'scanSlider';
            app.ScansSlider.Position = [179 309 147 3];

            % Create ViewModeButtonGroup
            app.ViewModeButtonGroup = uibuttongroup(app.UIFigure);
            app.ViewModeButtonGroup.SelectionChangedFcn = createCallbackFcn(app,@applyViewPrefs,true);
            app.ViewModeButtonGroup.Title = 'View Mode';
            app.ViewModeButtonGroup.Tag = 'viewMode';
            app.ViewModeButtonGroup.FontWeight = 'bold';
            app.ViewModeButtonGroup.Position = [179 162 158 106];

            % Create FirstinRangeButton
            app.FirstinRangeButton = uiradiobutton(app.ViewModeButtonGroup);
            app.FirstinRangeButton.Text = 'First in Range';
            app.FirstinRangeButton.Tag = 'viewFirst';
            app.FirstinRangeButton.Position = [11 60 96 22];
            app.FirstinRangeButton.Value = true;

            % Create AverageButton
            app.AverageButton = uiradiobutton(app.ViewModeButtonGroup);
            app.AverageButton.Text = 'Average';
            app.AverageButton.Tag = 'viewAvg';
            app.AverageButton.Position = [11 38 66 22];

            % Create StackedButton
            app.StackedButton = uiradiobutton(app.ViewModeButtonGroup);
            app.StackedButton.Text = 'Stacked';
            app.StackedButton.Position = [11 16 66 22];

            % Create ChannelLabel
            app.ChannelLabel = uilabel(app.UIFigure);
            app.ChannelLabel.HorizontalAlignment = 'right';
            app.ChannelLabel.FontWeight = 'bold';
            app.ChannelLabel.Position = [172 347 55 22];
            app.ChannelLabel.Text = 'Channel:';

            % Create ChannelDropDown
            app.ChannelDropDown = uidropdown(app.UIFigure);
            app.ChannelDropDown.Position = [232 347 100 22];

            % Create ExperimentLabel
            app.ExperimentLabel = uilabel(app.UIFigure);
            app.ExperimentLabel.FontSize = 14;
            app.ExperimentLabel.FontWeight = 'bold';
            app.ExperimentLabel.Position = [218 385 81 22];
            app.ExperimentLabel.Text = 'Experiment';

            % Create Phi0SpinnerLabel
            app.Phi0SpinnerLabel = uilabel(app.UIFigure);
            app.Phi0SpinnerLabel.HorizontalAlignment = 'right';
            app.Phi0SpinnerLabel.Position = [179 95 32 22];
            app.Phi0SpinnerLabel.Text = 'Phi 0';

            % Create Phi0Spinner
            app.Phi0Spinner = uispinner(app.UIFigure);
            app.Phi0Spinner.Step = 1;
            app.Phi0Spinner.ValueChangedFcn = createCallbackFcn(app,@handlePhase,true);
            app.Phi0Spinner.Position = [226 95 59 22];

            % Create Phi1SpinnerLabel
            app.Phi1SpinnerLabel = uilabel(app.UIFigure);
            app.Phi1SpinnerLabel.HorizontalAlignment = 'right';
            app.Phi1SpinnerLabel.Position = [179 62 32 22];
            app.Phi1SpinnerLabel.Text = 'Phi 1';

            % Create Phi1Spinner
            app.Phi1Spinner = uispinner(app.UIFigure);
            app.Phi1Spinner.Step = 0.01;
            app.Phi1Spinner.ValueChangedFcn = createCallbackFcn(app,@handlePhase,true);
            app.Phi1Spinner.Position = [226 62 59 22];

            % Create PivotSpinnerLabel
            app.PivotSpinnerLabel = uilabel(app.UIFigure);
            app.PivotSpinnerLabel.HorizontalAlignment = 'right';
            app.PivotSpinnerLabel.Position = [179 128 32 22];
            app.PivotSpinnerLabel.Text = 'Pivot';

            % Create PivotSpinner
            app.PivotSpinner = uispinner(app.UIFigure);
            app.PivotSpinner.Position = [226 128 59 22];
            app.PivotSpinner.ValueChangedFcn = createCallbackFcn(app,@handlePhase,true);

            % Create AbsoluteCheckBox
            app.AbsoluteCheckBox = uicheckbox(app.UIFigure);
            app.AbsoluteCheckBox.Text = 'Absolute';
            app.AbsoluteCheckBox.Tag = 'abs/real/imag';
            app.AbsoluteCheckBox.ValueChangedFcn = createCallbackFcn(app,@applyViewPrefs,true);
            app.AbsoluteCheckBox.Position = [447 428 69 22];
            app.AbsoluteCheckBox.Value = true;

            % Create RealCheckBox
            app.RealCheckBox = uicheckbox(app.UIFigure);
            app.RealCheckBox.Text = 'Real';
            app.RealCheckBox.Tag = 'abs/real/imag';
            app.RealCheckBox.ValueChangedFcn = createCallbackFcn(app,@applyViewPrefs,true);
            app.RealCheckBox.Position = [539 428 46 22];

            % Create ImaginaryCheckBox
            app.ImaginaryCheckBox = uicheckbox(app.UIFigure);
            app.ImaginaryCheckBox.Text = 'Imaginary';
            app.ImaginaryCheckBox.ValueChangedFcn = createCallbackFcn(app,@applyViewPrefs,true);
            app.ImaginaryCheckBox.Tag = 'abs/real/imag';
            app.ImaginaryCheckBox.Position = [626 428 74 22];

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = BrukerAnalysis

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end