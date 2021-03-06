
if ~isfield(options,'appearance')
	% use prediction on a subset of columns to restrict the area that has to be taken into consideration
	if length(collector.options.columnsPred) > 50 && isfield(collector.options,'margins')
		volRegion = 1;
		if numVolRegions > 1
			error('Not implemented yet for 3D models');
		end
		columnsPred = collector.options.columnsPred; % save for later use
		subVec = round(linspace(1+10,numColumnsPred-10,15)); % the subset of columns used for the initial prediction
		collector.options.columnsPred = collector.options.columnsPred(subVec);

		% fetch appearance Terms
		predictionSparse = predAppearance(files(file),collector,models.appearanceModel,options);
		prediction = permute(reshape(predictionSparse.prediction{volRegion},[numClasses,collector.options.Y,length(collector.options.columnsPred)]),[2 1 3]);
		prediction = prediction(:,length(collector.options.LayersPred) + (1:length(collector.options.EdgesPred)),:);

		% predict q_c
      	idxA = columnsPredShape{volRegion}(1,subVec)-1;
%		idxA = (1:length(subVec))-1; idxB = repmat(columnsPredShape{volRegion}(1,subVec),numBounds,1)' + repmat((0:(numBounds-1))*numColumnsShape,length(subVec),1);
		boundsPred = [zeros(1,length(idxA)); ones(1,length(idxA))*(numRows-1)];
        q_c_init = permute(reshape(sumProductSparseC(prediction(:,:,:),models.shapeModel(volRegion).mu,models.shapeModel(volRegion).WML,models.shapeModel(volRegion).sigmaML,int32(idxA),hashTable,int32(boundsPred)),[numRows,numBounds,length(subVec)]),[3 2 1]);

		% obtain estimated boundaries
		z = size(q_c_init);
		boundsInit = squeeze(sum(permute(q_c_init,[2 3 1]).*repmat(1:numRows,[numBounds,1,length(subVec)]),2))';

		% obtain quality of estimate
		for k = 1:numBounds
			for j = 1:length(subVec)
				I = find(q_c_init(j,k,:)>=10^-30);
				tmp = squeeze(q_c_init(j,k,I))'.*squeeze(log(prediction(I,k,j)))';
				q_c_data(j,k) = -full(sum(tmp(~isnan(tmp)&~isinf(tmp))));
			end
		end

		% which entries do we trust?
		idxTrust = q_c_data - repmat(collector.options.margins.mu(4,:),length(subVec),1)-repmat(collector.options.margins.sigma(4,:),length(subVec),1)*1 < 0;

		% if several b-scan columns map to the same shape prior column we select a unique one here
		[C IA] = unique(columnsShapePred{1}(subVec));
		idxTrust = idxTrust(IA,:); boundsInit = boundsInit(IA,:);
		idxGiven = repmat(C',1,numBounds)+repmat((0:(numBounds-1))*numColumnsShape,length(C),1);
		idxGiven = idxGiven(idxTrust);
		% get indices from the first and last boundary
		idxCond = setdiff([[1:numColumnsShape] [1:numColumnsShape]+numColumnsShape*(numBounds-1)],[C(idxTrust(:,1)),C(idxTrust(:,end))+numColumnsShape*(numBounds-1)]); 
		% obtain posterior mean
		Sigma_b_b = sigmaML*eye(length(idxGiven)) + WML(idxGiven,:)*WML(idxGiven,:)'; 
		Sigma_a_b = WML(idxCond,:)*WML(idxGiven,:)'; 
		mu_a_b = models.shapeModel.mu(idxCond) + Sigma_a_b*inv(Sigma_b_b)*(boundsInit(idxTrust)-models.shapeModel.mu(idxGiven));
		idxGiven = [C(idxTrust(:,1)),C(idxTrust(:,end))+numColumnsShape];	
		idxCond(idxCond>numColumnsShape)= idxCond(idxCond>numColumnsShape) - numColumnsShape*(numBounds-2);

		boundsFull(idxCond) = mu_a_b;
		boundsFull(setdiff(1:numColumnsShape*2,idxCond)) = [boundsInit(idxTrust(:,1),1); boundsInit(idxTrust(:,end),end)];
		boundsPred = round(reshape(boundsFull,numColumnsShape,2) + [-25*ones(numColumnsShape,1) 25*ones(numColumnsShape,1)]);
		collector.options.columnsPred = columnsPred;

		% create idxSet that contains positions of patches
		idxSet = zeros(2,sum(boundsPred(:,2)-boundsPred(:,1)+1));
		tmp = [arrayfun(@(x,y,z) ones(1,y-x+1)*z,boundsPred(:,1),boundsPred(:,2),collector.options.columnsPred','UniformOutput',false)];
		idxSet(2,:) = [tmp{:}];
		tmp = [arrayfun(@(x,y) colon(x,y),boundsPred(:,1),boundsPred(:,2),'UniformOutput',false)];
		idxSet(1,:) = [tmp{:}];
		collector.options.idxSet = idxSet;
		
		% fetch appearance terms
		prediction = predAppearance(files(file),collector,models.appearanceModel,options);
		predictionA.prediction{1} = zeros(size(prediction.prediction{1},1),numColumnsPred*collector.options.Y);
		% change the index over columns from the real B-Scan to columnsPred
		idxChange = zeros(1,collector.options.X);
		idxChange(collector.options.columnsPred) = 1:numColumnsPred;
		idxSet(2,:) = idxChange(idxSet(2,:));
		IND = sub2ind([collector.options.Y numColumnsPred],idxSet(1,:),idxSet(2,:));
		predictionA.prediction{1}(:,IND) = prediction.prediction{1};
	else
		boundsPred = [ones(numColumnsShape,1)  ones(numColumnsShape,1)*numRows];
		predictionA = predAppearance(files(file),collector,models.appearanceModel,options);
	end
else
	predictionA.prediction = options.appearance;
end

prediction = zeros(numRows,numClasses,numColumnsPred,numVolRegions);

for volRegion = 1:numVolRegions
	% load ground truth and the scan itself
	collector.options.labelID = collector.options.labelIDs(file,volRegion);
	% load labels if set by the user
	if collector.options.loadLabels
		output.trueLabels{file,volRegion} = loadLabels(files(file).name,collector.options);
	end

	if options.plotting
		eval(sprintf('B%d = loadData(files(file).name,collector.options);',collector.options.labelID));
	end
	prediction(:,:,:,volRegion) = permute(reshape(predictionA.prediction{volRegion},[numClasses,collector.options.Y,numColumnsPred]),[2 1 3]);
end
% we only need the subset of boundary classes
prediction = prediction(:,length(collector.options.LayersPred) + (1:length(collector.options.EdgesPred)),:,:);
% renormalize
%prediction = prediction./repmat(sum(prediction,2),[1 numBounds 1 1]);
% reduce the precision
prediction(prediction < options.thresholdAccuracy) = 0;

% outputs pixelwise appearance terms too
if collector.options.saveAppearanceTerms
	output.appearanceTerms.prediction{file} = single(predictionA.prediction{1});
	if collector.options.loadLabels
		output.appearanceTerms.trueLabels{file} = single(predictionA.trueLabels{1});
	end
end
clear predictionA;

initqc = tic;

if isfield(options,'segmentation')
	if numVolRegions > 1
		error('Not implemented for 3D models');
	end
	% all columns with at least one boundary to segment
	columnsToSegment = find(sum(options.idxRecalc)>0);

	%if ~isfield(models.shapeModel,'pTransV')
	%	models.shapeModel = preCalcTransitionMatrices(collector,models.shapeModel,10^-20);
	%	end
	for j = 1:length(columnsToSegment)
		i = columnsToSegment(j);
		% calculate transition matrices
	    for k = 2:numBounds
			idx_a = columnsPredShape{1}(1,i) + (k-2)*numColumnsShape; idx_b = idx_a + numColumnsShape;

			P = inv(WML([idx_a idx_b],:)*WML([idx_a idx_b],:)' + eye(2)*(sigmaML+40));
			[iS jS sS numElements] = getCondTransMatrixC([models.shapeModel.mu(idx_a) models.shapeModel.mu(idx_b)]',P,int32(collector.options.Y),10^-20);
			pTransV{k} = sparse(iS(1:numElements),jS(1:numElements),sS(1:numElements),collector.options.Y,collector.options.Y);
		end

		% clamp observation probabilities to previous segmentation
		idxA = sum(numColumnsShape(1:volRegion-1))*numBounds + i;
		pObs = squeeze(prediction(:,:,i,volRegion));
		fixBounds = find(~options.idxRecalc(:,columnsToSegment(j)));
		for k = 1:length(fixBounds)
			pObs(:,fixBounds(k)) = zeros(numRows,1);
			segm = options.segmentation(fixBounds(k),columnsToSegment(j));
			pObs([floor(segm) ceil(segm)],fixBounds(k)) = [ceil(segm)-segm segm-floor(segm)];
		end
		
		variance = sum(models.shapeModel.WML(idxA,:).^2) + models.shapeModel.sigmaML;
		% calculate prior probabilities for first boundary
		pStart = 1/sqrt(2*pi*variance)*exp(-0.5*(1/variance)*((1:numRows) - models.shapeModel.mu(idxA)).^2);
		q_c.singleton(:,:,i,volRegion) = sumProductSparse(pStart,pTransV,pObs);
	end
else
	% old Matlab code
	if 0
		if ~isfield(models.shapeModel,'pTransV')
			models.shapeModel = preCalcTransitionMatrices(collector,models.shapeModel,10^-20);
		end
		for volRegion = 1:numVolRegions
			% initialization only has to be made for columns relvant for updating the q(b) distribution
			for i = 1:numColumnsShape(volRegion)
				idxA = sum(numColumnsShape(1:volRegion-1))*numBounds + i;
				pObs = squeeze(prediction(:,:,columnsShapePred{volRegion}(i),volRegion));
	
				variance = sum(models.shapeModel.WML(idxA,:).^2) + models.shapeModel.sigmaML;
				% calculate probabilities for first boundary
				pStart = 1/sqrt(2*pi*variance)*exp(-0.5*(1/variance)*((1:numRows) - models.shapeModel.mu(idxA)).^2);
				q_c.singleton(:,:,columnsShapePred{volRegion}(i),volRegion) = sumProductSparse(pStart,models.shapeModel.pTransV{volRegion}(i,:),pObs);
			end
		end
	end
	% C version; segments all columns for one BScan; needs as input the indices of the first boundary inside the shape model
	for volRegion = 1:numVolRegions
		% the -1 is C-indexing
		idxA = sum(numColumnsShape(1:volRegion-1))*numBounds + (1:numColumnsShape(volRegion)) - 1;
		q_c.singleton(:,:,columnsShapePred{volRegion},volRegion) = reshape(sumProductSparseC(prediction(:,:,columnsShapePred{volRegion},volRegion),models.shapeModel(volRegion).mu,models.shapeModel(volRegion).WML,models.shapeModel(volRegion).sigmaML,int32(idxA),hashTable,int32(boundsPred')-1),[numRows,numBounds,numColumnsShape(volRegion)]);
		% column-wise C-code (used only for testing)
		%	offset = numColumnsShape(volRegion)*[0:numBounds-2];
		% initialization only has to be made for columns relvant for updating the q(b) distribution
		%	for i = 1:numColumnsShape(volRegion)
		%		% the -1 is C-indexing
		%		idxA = sum(numColumnsShape(1:volRegion-1))*numBounds + i - 1;
		%		idxA = [idxA+offset; idxA+offset+numColumnsShape(volRegion)];
		%		pObs = squeeze(prediction(:,:,columnsShapePred{volRegion}(i),volRegion));
		%		
		%		q_c.singleton2(volRegion,columnsShapePred{volRegion}(i),:,:) = reshape(sumProductSparseBackup(pObs,models.shapeModel(volRegion).mu,models.shapeModel(volRegion).WML,models.shapeModel(volRegion).sigmaML,int32(idxA),hashTable),[numRows numBounds])';
		%	end
	end
end
q_c.singleton(q_c.singleton < options.threshold_q_c) = 0;

if collector.options.printTimings
	fprintf('[Initialized q_c]: %.3fs\n',toc(initqc));
end



