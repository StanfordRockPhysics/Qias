classdef Qias
%% Qias:
% Unit Conversion in Matlab with the ability to quickly add new units. The 
% code is based on graph theory to determine the relationships between 
% units. Because of this, only one conversion factor need to be provided 
% for each new unit. The code can relate to other units automatically.
%
% Mustafa Al Ibrahim @ 2018
% Mustafa.Geoscientist@outlook.com

%% Properties
% Properties used to hold the information of the library. In this case, it
% holds the graphs used in the unit conversion.

    properties (Access = private)
        Graphs = containers.Map;
        Units = [];
    end
    
%% Methods (instance)
% This are the main functions of the library that the user interact with.
% The engine of the library is in the static methods section.

    methods
        
        % ============================================
        function obj = Qias(isOptimize, graphsFolder)
            
            % Defaults
            if ~exist('isOptimize', 'var'); isOptimize = false; end
            if ~exist('graphsFolder', 'var')
                libraryFolder = fileparts(mfilename('fullpath'));
                graphsFolder  = fullfile(libraryFolder, 'Graphs');
            end
            
            % Assertions
            assert(isa(isOptimize, 'logical') && isscalar(isOptimize), 'isOptimize must be logical scalar');
            
            % Main
            properties = Qias.graphNamesFromFolder(graphsFolder);
            for i = 1:numel(properties)
                fileName = fullfile(graphsFolder, [properties{i}, '.csv']);
                Graph = Qias.graphLoad(fileName);
                assert(all(conncomp(Graph)==1), 'Graph is not connected. Make sure the input data is correct');
                obj.Graphs(properties{i}) = Graph;
            end
            
            % Optimize if requested
            if isOptimize == true; obj.optimize(); end
            
            % Accumulate all units
            obj.Units = obj.getAllUnits();
            
        end
        % ============================================
        function Graph = getGraph(obj, property)
            assert(ismember(property,keys(obj.Graphs)), 'Graph not found');
            Graph = obj.Graphs(property); 
        end
        % ============================================
        function units = getUnits(obj, property)
            units = obj.Units;

            if exist('property', 'var')
                units = units(ismember(units.Property, property), :);
            end
        end
        % ============================================
        function properties = getProperties(obj)
            properties = keys(obj.Graphs);
        end
        % ============================================
        function [valueUnitTo, multiplier, property, pathUsed] = convert(obj, valueUnitFrom, unitFrom, unitTo, property)
            
            if ~exist('property', 'var')
                properties = obj.unit2Property(unitFrom, unitTo);
                property   = obj.checkPropertyAndPrompt(properties);
            end
            
            Graph = obj.getGraph(property);
            [valueUnitTo, multiplier, pathUsed] = Qias.graphConvert(valueUnitFrom, unitFrom, unitTo, Graph);
        
        end
        % ============================================
        function [multiplier, property, pathUsed] = getMultiplier(obj, unitFrom, unitTo, property)
            
            if ~exist('property', 'var')
                properties = obj.unit2Property(unitFrom, unitTo);
                property   = obj.checkPropertyAndPrompt(properties);
            end
            
            Graph = obj.getGraph(property);
            [multiplier, pathUsed] = Qias.graphGetMultiplier(Graph, unitFrom, unitTo);
            
        end
        % ============================================
        function [] = optimize(obj)
            % Note: optimization might take time but it will make
            % subsequent convertion much faster. This is useful if the 
            % conversion function will be called a lot.
            properties = obj.getProperties();
            for i = 1:numel(properties)
                obj.Graphs(properties{i}) = Qias.graphOptimize(obj.Graphs(properties{i}));
            end           
        end
        % ============================================
        function [axisHandle] = plot(obj, property)
            Graph = obj.getGraph(property);
            [axisHandle] = Qias.graphPlot(Graph);
        end
        % ============================================

    end
    
%% Methods (private)
% The static methods operate the object but they are not exposed to the
% user. They are support functions

    methods (Access = private)
        
        function properites = unit2Property(obj, unitFrom, unitTo)
            unitFromIndex = ismember(obj.Units.Name, unitFrom);
            unitToIndex = ismember(obj.Units.Name, unitTo);   
            unitFromProperty = obj.Units.Property(unitFromIndex);
            unitToProperty = obj.Units.Property(unitToIndex);
            properites = intersect(unitFromProperty, unitToProperty);
        end
        % ============================================
        function property = checkPropertyAndPrompt(obj, properties)
            if numel(properties) ==1
                property = properties{1};
            elseif numel(properties) == 0
                error('Units not found in the same property');
            else                   
                disp('Found more than one property'); disp(char(properties));
                error('Choose a specific property when calling the function');
            end                     
        end
        % ============================================
        function allUnits = getAllUnits(obj)
            properties = obj.getProperties();
            allUnits = cell2table(cell(0,3), 'VariableNames', {'Name','FullName', 'Property'});
            for i = 1:numel(properties)
                Graph = obj.getGraph(properties{i});
                units = Qias.graphUnits(Graph);
                units.Property = repmat({properties{i}}, size(units,1),1);
                allUnits = vertcat(allUnits, units);
            end
        end
        % ============================================
   
    end
    
%% Methods (static)
% The static methods operate mostly on one graph. They are useful for using
% the library without instantiation. They are also useful for internal
% testing of the code. Casual user does not need to use them. All function
% names start with "graph" 

    methods (Static)
        
        % ============================================
        function graphsName = graphNamesFromFolder(folder)
            
            % Assertions
            assert(exist('folder', 'var')==true && exist(folder, 'dir') == 7, 'Folder does not exist');
            
            % Main
            fileListing   = ls(fullfile(folder, '*.csv'));
            nFiles = size(fileListing,1);
            assert(nFiles>0, 'No files found in folder');
            
            graphsName = cell(nFiles,1);
            for i = 1:nFiles
                graphName = strtrim(fileListing(i,:));
                graphsName{i} = graphName(:,1:end-4);
            end
        end
        % ============================================
        function Graph = graphLoad(fileName)
            
            % Assertions
            assert(exist('fileName', 'var')==true && exist(fileName, 'file') ==2, 'File does not exist');
            
            % Read table
            graphTable = readtable(fileName);
            
            % Create inverse graph
            graphTableInverse = graphTable;
            graphTableInverse(:,1:2) = graphTable(:,3:4);
            graphTableInverse(:,3:4) = graphTable(:,1:2);
            graphTableInverse{:,5} = 1./graphTableInverse{:,5};

            % Combine the graphs and insert them into a graph
            fullGraphTable = [graphTable; graphTableInverse];
            Graph = digraph(fullGraphTable{:,1}, fullGraphTable{:,3}, fullGraphTable{:,5});
            
            % Store unit info
            units = table2cell(Graph.Nodes);
            [~,Locb] = ismember(units, fullGraphTable{:,1});
            unitsName = fullGraphTable{Locb,2};
            infoTable = cell2table([units, unitsName], 'VariableName', {'Name', 'FullName'});
            Graph.Nodes = infoTable;
        end    
        % ============================================
        function [valueUnitTo, multiplier, pathUsed] = graphConvert(valueUnitFrom, unitFrom, unitTo, Graph)
            
            % Assertions
            assert(exist('valueUnitFrom','var')==true && isnumeric(valueUnitFrom), 'valueUnitFrom must be numeric');
            assert(exist('unitFrom','var')==true && ischar(unitFrom), 'unitFrom must be a string');
            assert(exist('unitTo','var')==true && ischar(unitTo), 'unitTo must be a string');
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            
            % Main

            [multiplier, pathUsed] = Qias.graphGetMultiplier(Graph, unitFrom, unitTo);     
            valueUnitTo = valueUnitFrom * multiplier;
            
        end
        % ============================================
        function [multiplier, pathUsed] = graphGetMultiplier(Graph, unitFrom, unitTo)
            
            directIndex = findedge(Graph, unitFrom, unitTo);
            if directIndex ~= 0
                multiplier = Graph.Edges.Weight(directIndex);
                pathUsed       = {unitFrom, unitTo};
            else
                pathUsed = shortestpath(Graph, unitFrom, unitTo, 'Method','unweighted');
                idxOut = findedge(Graph,pathUsed(1:end-1)',pathUsed(2:end)');
                multiplier = prod(Graph.Edges.Weight(idxOut));
            end
        end
        % ============================================
        function units = graphUnits(Graph, isOnlyUnitName)
            if ~exist('isOnlyUnitName', 'var'); isOnlyUnitName = false; end
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            units = sortrows(Graph.Nodes);
            if isOnlyUnitName
                units = units.Name;
            end
        end
        % ============================================
        function [axisHandle] = graphPlot(Graph)
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            
            figure('Color', 'White')
            edgeLabels = arrayfun(@(x) sprintf('%0.2g', x),Graph.Edges.Weight,...
                'UniformOutput', false);
            axisHandle = plot(Graph, 'Layout','force', 'EdgeLabel',edgeLabels);
            axisHandle.EdgeColor  = 'r';

            set(gca,'xticklabel',{[]}, 'yticklabel', {[]});
        end
        % ============================================
        function Graph = graphOptimize(Graph)
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            
            % Main
            units = Qias.graphUnits(Graph, true);
            nUnits = numel(units);
            
            combinations = nchoosek(1:nUnits,2);
            for i = 1:size(combinations,1)
                [unitFrom, unitTo] = units{combinations(i,:)};
                directIndex = findedge(Graph, unitFrom, unitTo);
                
                if (directIndex == 0)
                    [~, multiplier] = Qias.graphConvert(1, unitFrom, unitTo, Graph);
                    from = {unitFrom,unitTo};
                    to   = {unitTo, unitFrom};
                    multiplier = [multiplier, 1./multiplier];
                    Graph = addedge(Graph,from,to,multiplier);
                end
            end

        end
        % ============================================
    end

end