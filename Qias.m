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
            graphsName = Qias.graphNamesFromFolder(graphsFolder);
            for i = 1:numel(graphsName)
                fileName = fullfile(graphsFolder, [graphsName{i}, '.csv']);
                Graph = Qias.graphLoad(fileName);
                assert(all(conncomp(Graph)==1), 'Graph is not connected. Make sure the input data is correct');
                obj.Graphs(graphsName{i}) = Graph;
            end
            
            % Optimize if requested
            if isOptimize == true; obj.optimize(); end
            
        end
        % ============================================
        function Graph = getGraph(obj, graphName)
            assert(ismember(graphName,keys(obj.Graphs)), 'Graph not found');
            Graph = obj.Graphs(graphName); 
        end
        % ============================================
        function units = getUnits(obj, graphName)
            Graph = obj.getGraph(graphName);
            units = Qias.graphUnits(Graph);
        end
        % ============================================
        function properties = getProperties(obj)
            properties = keys(obj.Graphs);
        end
        % ============================================
        function [valueUnitTo, multiplier, pathUsed] = convert(obj, valueUnitFrom, unitFrom, unitTo, graphName)
            Graph = obj.getGraph(graphName);
            [valueUnitTo, multiplier, pathUsed] = Qias.graphConvert(valueUnitFrom, unitFrom, unitTo, Graph);
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
        function [axisHandle] = plot(obj, graphName)
            Graph = obj.getGraph(graphName);
            [axisHandle] = graphPlot(Graph);
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
            fileListing   = dir(fullfile(folder, '*.csv'));
            fileListing =  struct2table(fileListing);
            graphsName = cellfun(@(x) x(1:end-4), fileListing.name, 'UniformOutput', false);
        end
        % ============================================
        function Graph = graphLoad(fileName)
            
            % Assertions
            assert(exist('fileName', 'var')==true && exist(fileName, 'file') ==2, 'File does not exist');
            
            % Read table
            graphTable = readtable(fileName);
            
            % Create inverse graph
            graphTableInverse = graphTable;
            graphTableInverse(:,1) = graphTable(:,2);
            graphTableInverse(:,2) = graphTable(:,1);
            graphTableInverse{:,3} = 1./graphTableInverse{:,3};

            % Combine the graphs and insert them into a graph
            fullGraphTable = [graphTable; graphTableInverse];
            Graph = digraph(fullGraphTable{:,1}, fullGraphTable{:,2}, fullGraphTable{:,3});  
        end    
        % ============================================
        function [valueUnitTo, multiplier, pathUsed] = graphConvert(valueUnitFrom, unitFrom, unitTo, Graph)
            
            % Assertions
            assert(exist('valueUnitFrom','var')==true && isnumeric(valueUnitFrom), 'valueUnitFrom must be numeric');
            assert(exist('unitFrom','var')==true && ischar(unitFrom), 'unitFrom must be a string');
            assert(exist('unitTo','var')==true && ischar(unitTo), 'unitTo must be a string');
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            
            % Main
            directIndex = findedge(Graph, unitFrom, unitTo);
            if directIndex ~= 0
                multiplier = Graph.Edges.Weight(directIndex);
                pathUsed       = {unitFrom, unitTo};
            else
                pathUsed = shortestpath(Graph, unitFrom, unitTo, 'Method','unweighted');
                idxOut = findedge(Graph,pathUsed(1:end-1)',pathUsed(2:end)');
                multiplier = prod(Graph.Edges.Weight(idxOut));
            end
                
            valueUnitTo = valueUnitFrom * multiplier;
            
        end
        % ============================================
        function units = graphUnits(Graph)
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            units = table2cell(Graph.Nodes);
        end
        % ============================================
        function [axisHandle] = graphPlot(Graph)
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            axisHandle = plot(Graph, 'Layout','force', 'EdgeLabel',Graph.Edges.Weight);
        end
        % ============================================
        function Graph = graphOptimize(Graph)
            assert(exist('Graph','var')==true && isa(Graph, 'digraph'), 'Graph must be a digraph');
            
            % Main
            units  = table2cell(Graph.Nodes); 
            nUnits = numel(Graph.Nodes);
            
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