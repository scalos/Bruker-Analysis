classdef ProcSetter <handle

    properties
        procStep
        dataObj
        initFun
        updateFun
        isActiveFun
        applyFun
        viewerObj
    end

    methods
        function obj = ProcSetter(procStep,dataObj,initFun,updateFun,applyFun,isActiveFun,opts)
            arguments
                procStep ProcStep
                dataObj DataObject
                initFun function_handle
                updateFun function_handle
                applyFun function_handle
                isActiveFun function_handle
                opts.viewerObj = [];
            end
            obj.procStep = procStep;
            obj.dataObj = dataObj;
            obj.initFun = initFun;
            obj.updateFun = updateFun;
            obj.applyFun = applyFun;
            obj.isActiveFun = isActiveFun;
            obj.viewerObj = opts.viewerObj;
        end
        function apply(obj)
            obj.applyFun(obj);
        end
        function init(obj)
            obj.initFun(obj);
        end
        function update(obj)
            obj.updateFun(obj);
        end
        function tf = isActive(obj)
            tf = obj.isActiveFun(obj);
        end
    end
end