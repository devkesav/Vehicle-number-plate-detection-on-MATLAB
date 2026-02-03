clc; clear; close all;

%% =========================
% 1. Load Vehicle Image
%% =========================
[file,path] = uigetfile({'*.jpg;*.png;*.bmp'},'Select Vehicle Image');
if isequal(file,0)
    disp('User canceled'); return;
end

img = imread(fullfile(path,file));
figure, imshow(img), title('Original Image');

%% =========================
% 2. Convert to Grayscale
%% =========================
if size(img,3) == 3
    gray = rgb2gray(img);
else
    gray = img;
end

%% =========================
% 3. Define ROI (bottom half)
%% =========================
[r,c] = size(gray);
roi = gray(round(r*0.2):r, :);  
roiOffset = round(r*0.2);

%% =========================
% 4. Enhance Contrast
%% =========================
roi = adapthisteq(roi);

%% =========================
% 5. Edge Detection
%% =========================
edges = edge(roi,'canny');

%% =========================
% 6. Morphology
%% =========================
se = strel('rectangle',[5 15]);
bw = imclose(edges,se);
bw = imfill(bw,'holes');
bw = bwareaopen(bw,1000);

figure, imshow(bw), title('Binary Morphology');

%% =========================
% 7. Label Regions
%% =========================
[L,num] = bwlabel(bw);
stats = regionprops(L,'BoundingBox','Area','Solidity');

disp(['Total regions found: ', num2str(num)]);

%% =========================
% 8. Select Plate Candidate
%% =========================
plateBox = [];
bestScore = 0;

for i = 1:num
    bb = stats(i).BoundingBox;
    aspect = bb(3)/bb(4);
    
    if aspect > 1.5 && aspect < 6.5 && stats(i).Area>1000 && stats(i).Solidity>0.25
        score = stats(i).Area * stats(i).Solidity;
        if score > bestScore
            bestScore = score;
            plateBox = bb;
        end
    end
end

%% =========================
% 9. Extract Plate and Expand Bounding Box
%% =========================
if ~isempty(plateBox)
    % Expand bounding box slightly
    x = max(1, plateBox(1)-5);
    y = max(1, plateBox(2)-5);
    w = min(size(roi,2)-x, plateBox(3)+10);
    h = min(size(roi,1)-y, plateBox(4)+10);

    LP = imcrop(roi,[x y w h]);
    figure, imshow(LP), title('Detected License Plate');

    % Draw rectangle on original image
    figure, imshow(img), title('License Plate Detection'); hold on;
    rectangle('Position',[x, y+roiOffset, w, h],'EdgeColor','r','LineWidth',2);
    hold off;

    %% =========================
    % 10. Deskew Plate
    %% =========================
    LP_mask = imbinarize(LP);
    stats_lp = regionprops(LP_mask,'Orientation');
    if ~isempty(stats_lp)
        angle = -stats_lp(1).Orientation;
        LP = imrotate(LP, angle, 'bilinear','crop');
    end

    %% =========================
    % 11. Preprocess for OCR
    %% =========================
    LP_gray = imresize(LP,[200 500]);  
    LP_bw = imbinarize(LP_gray,'adaptive','ForegroundPolarity','dark','Sensitivity',0.5);
    LP_bw = imopen(LP_bw, strel('rectangle',[3 2]));
    LP_bw = imclose(LP_bw, strel('rectangle',[3 5]));
    
    if mean(LP_bw(:)) > 0.5
        LP_bw = imcomplement(LP_bw);
    end
    figure, imshow(LP_bw), title('Optimized Plate for OCR');

    %% =========================
    % 12. OCR Recognition
    %% =========================
    LP_ocr = uint8(LP_bw)*255;
    results = ocr(LP_ocr,'CharacterSet','ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-');
    plateText = results.Text;

    % Clean OCR output
    plateText = strrep(plateText,char(10),'');
    plateText = strrep(plateText,' ','');
    plateText = strrep(plateText,':','');
    plateText = strrep(plateText,',','');

    % Correct common OCR mistakes
    plateText = upper(plateText);
    plateText = strrep(plateText,'O','0'); % O→0
    plateText = strrep(plateText,'I','1'); % I→1
    plateText = strrep(plateText,'L','1'); % L→1

    %% =========================
    % 13. Regex to extract valid Indian plate
    %% =========================
    expr = '[A-Z]{2}-[0-9]{1,2}-[A-Z]{1,2}-[0-9]{1,4}';
    match = regexp(plateText, expr, 'match');

    if ~isempty(match)
        plateText = match{1};  % take first valid match
    end

    disp(['Cleaned Plate Number: ', plateText]);
    msgbox(['Vehicle Plate Number: ', plateText],'Plate Recognition');

else
    disp('No License Plate Detected');
end