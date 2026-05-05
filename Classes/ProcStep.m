classdef ProcStep<handle

    properties
        tag
        fun
        cacheable
        cachedState
        scope
        params
        dataObj = [];
        setter = []
    end

    properties(SetAccess=private)
        params_old
    end

    methods
        function obj = ProcStep(fun,scope,opts)
            arguments
                fun (1,1) function_handle;
                scope {mustBeMember(scope,{'local','global'})};
                opts.cacheable (1,1) logical = false;
                opts.params cell = {};
                opts.tag string = '';
                opts.dataObj = [];
                opts.setFun = [];
            end
            obj.tag = opts.tag;

            %when called, fun must accept 2 arguments:
                %     obj: it's own ProcStep obj
                % dataObj: a dataObj object
                %    data: matrix to process
            obj.fun = fun;
            obj.scope = scope;
            obj.cacheable = opts.cacheable;
            obj.params = opts.params;
            obj.params_old = cell(size(obj.params));
            obj.cachedState = {};
            pSetter = opts.setFun;
            if ~isempty(pSetter)
                assert(isa(pSetter,'ProcSetter'));
            end
            obj.setter = pSetter;
            dataObj = opts.dataObj;
            if ~isempty(dataObj)
                obj.dataObj = dataObj;
            end
        end

        function set.dataObj(obj,dataObj)
            assert(isa(dataObj,'DataObject'),'ERROR: data object must be a member of the DataObject class');
            obj.dataObj = dataObj;
        end

        function launchSetter(obj)
            if isempty(obj.setter)
                warning('Step does not have an attached setter!');
                return;
            end
            assert(isa(obj.setter,'ProcSetter'),'ERROR: ProcStep setter must be member of ProcSetter class!');
            setter_ = obj.setter;
            setter_.init;
        end

        function setParams(obj,newParams)
            if obj.validateParams(newParams)
                obj.params = newParams;
            end
        end

        function tf = constInRegion(obj,region)
            %region is a cell array of index slices (focus). Returns
            %whether the step parameters are constant within a focal
            %region.
            tf = true;
            for idx = 1:numel(obj.params)
                p = obj.params{idx};
                p_reg = p(region{:});
                if ~all(p_reg==p_reg(1))
                    tf = false;
                    return;
                end
            end
        end

        function tf = validateParams(obj,newParams)
            tf = true;
            if ~iscell(newParams)
                tf = false;
            end
            if ~all(isequal(size(newParams),size(obj.params)))
                tf = false;
            end
            newParams_flat = newParams(:);
            objParams_flat = obj.params(:);
            for param = 1:numel(newParams_flat)
                if ~all(isequal(size(newParams_flat{param}),size(objParams_flat{param})))
                    tf = false;
                end
            end
        end

        function pData = processData(obj,data,opts)
            arguments
                obj
                data
                opts.updateParams (1,1) logical = true;
                opts.attemptCache (1,1) logical = true
            end
            fun_ = obj.fun;
            pData = fun_(obj,obj.dataObj,data);
            if isempty(pData)
                %something went wrong with function, don't update
                return;
            end
            if opts.updateParams
                obj.updateParams
            end
            if opts.attemptCache&&obj.cacheable
                obj.cacheState(pData);
            end
        end

        function updateParams(obj)
            obj.params_old = obj.params;
        end

        function cacheState(obj,state)
            obj.cachedState = state;
        end

        function tf = current(obj)
            tf = isequal(obj.params,obj.params_old);
        end
    end
end