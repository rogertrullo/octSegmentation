% this scripts demonstrates the usage of the labling tool using the example of the OCT-scan provided with the toolbox
% scriptFolder should point to the scripts folder of this toolbox 

% create default options
collector.options = setCollectorDefaults(struct(),[],[],[],[]);

% the ID of the B-scan (for Spectralis scans either 0 for 2-D or {0,...,61} for volumes)
collector.options.labelID = 0;
collector.options.loadRoutineData = 'spectralis';
collector.options.folder_data = scriptFolder;

% there are two possible sources for restoring labels
% labels that were established with the label tool and that can be found in saveDir (are provided)
collector.options.saveDir = scriptFolder; 
collector.options.loadRoutineLabels = 'LabelsFromLabelingTool'; 
% or if no label files are in saveDir, labels that are provided with the dataset
collector.options.folder_labels = scriptFolder;
collector.options.Y = 768;
collector.options.loadRoutineLabels = 'spectralisLabels'; 

% no preprocessing; we could add here a Gaussian filter for example or any other filter that eases labling
% see collector/preprocessing/scanlevel for available functions
collector.options.preprocessing.scanLevel = {};
% using existing labels? (if true, the labels in 'circularScan_0_coordinates' will be loaded)
restore = 1;
% we label the B-Scan with ID stored inside 'filename.mat';
labelTool('circularScan',collector,restore);
