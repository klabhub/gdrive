classdef gdrive
    % A Matlab wrapper around the gdrive tool
    %
    % Available from https://github.com/klabhub/gdrive
    % See README.md
    %
    %
    % BK - Nov 2018
    
    %% Properies definitions
    properties (SetAccess= protected)
        gExe  = ''; % The name of the gdrive executable (set on construction)
        configDir = ''; % Dir that contains gdrive configurarion info (Set on construction)
        
    end
    properties (Dependent)
        gExeCommand;
        about;  % Information about the gdrive
        config; % Security cofiguration
    end
    
    
    %% Dependent Properties
    methods
        function v = get.gExeCommand(o)
            if isempty(o.configDir)
                % Use default
                v = ['"' o.gExe '"'];
            else
                % Use specific
                v =  ['"' o.gExe '" -c "' o.configDir '"'];
            end
        end
        
        function v = get.about(o)
            % Return a struct with information on the current connection to
            % Google Drive 
            v =  o.do('about');
        end
        
        function v=get.config(o)
            % Return the authentication information.
            v = jsondecode(fileread(fullfile(o.configDir,"token_v2.json")));
        end
    end
    
    %% Public access methods
    methods (Access=public)
        function o = gdrive(config,exe)
            % Create a gdrive object.
            % config - optional. A directory to store/retrieve credentials
            % exe - optional. The gdrive executable. Defaults to one in the
            %                   mgdrive folder.
            if nargin>0
                o.configDir = config;
            end
            if nargin>1
                o.gExe = exe;
            else
                % Use the default exe
                o.gExe  =fullfile(fileparts(mfilename('fullpath')),gdrive.defaultExe);
            end
        end
        
        function [result,files] = info(o,str,id)
            % Retrieve information about a file on Google drive.
            % INPUT
            % str - The file name : '/Dir1/file.m'
            % id - The file ID (Google drive internal -internal use).
            % OUTPUT
            % result = structure with file infoamtion
            % files  = if 'str' is a directory, this will contain
            % information on the files inside that director (i.e. 'dir/ls')
            %
            if ~isempty(str)
                [pth,f,e] = fileparts(str);
                [files,parentID] =dir(o,str);
                if numel(files)==1 && strcmp(files.name,[f e])
                    if isempty(files.id)
                        % File/Dir not found
                        result = struct('id','','name',files.name,'path',pth,'parents',parentID);
                        return;
                    else
                        id = files.id;
                    end
                else % str was a dir with content. files contains that content
                    id  = parentID;
                end
            end
            result = o.do('info','', id);
            result.id = id; % info does not return this, add it.
        end
        
        function result = syncable(o)
            % Return all directories on the Google Drive that can be
            % synchronized.
            result  = o.do('sync list');
        end
        
        function result = makeDir(o,name,parentName,parentId)
            % Make a directory
            % name - the name of the directory
            % parentName - the name of the parent directory.
            % parentId - the ID of the parent directory - internal use.
            % OUTPUT
            % result - a structure with the id of the directory that was
            %           created.
            
            if ~isempty(parentName)
                parent =o.info(parentName) ;
                parentId = parent.id;
            else
                tmp = o.info('',parentId);
                parentName = fullfile('/',tmp.path);
            end
            
            % Check if the dir already exists.
            list = o.dir(parentName);
            ix =ismember(name,{list.name});
            if any(ix)
                warning(['Dir '  name ' already exists in ' parentName]);
                result = list(ix);
            else
                result = o.do('mkdir',[' --parent ' parentId],name);
            end
        end
        
        
        function result =syncUp(o,src,dst,dryRun)
            % Syncronize a local directory with a directory on Google
            % Drive. Note that this synchronization is somewhat limited,
            % files that are created "manually" on Google Drive are not
            % synced back down to the local drive.
            % INPUT
            % src - path to the source directory
            % dst - path to the directory that will contain the synced directory.
            % dryRun - toggle to only show the changes that would be made
            % (true) or actually do the sync (default: false).
            % OUTPUT
            % result  = struct array containing the log of changes.
            %               result(1)  is the   upload log
            %               result(2) is the download log.
            % EXMPLES
            % syncUp('c:\temp\data','/Share')
            %   will create a /Share/data and put everything that is in
            %   c:\temp\data into that directory.
            
            if ~exist(src,'dir') == 7
                error([src ' does not exist or not a dir. Nothing to sync?']);
            end
            if nargin <4
                dryRun= false;
            end
            [~,trgName] =fileparts(src);
            
            alreadySyncing = o.syncable;
            if dryRun
                dryRunStr = '--dry-run';
            else
                dryRunStr = '';
            end
            % Check in the target dir on  drive
            [dstInfo,dstList] = info(o,dst);
            if isempty(dstInfo)
                error([ dst ' does not exist. Create it first, the  ' src ' directory will be created inside it to sync'])
            else
                ix =strcmp(trgName,{dstList.name});
                if any(ix)
                    % A dir with this name already exist
                    if ismember(dstList(ix).id,{alreadySyncing.id})
                        % OK this is a syncable
                        trgId = dstList(ix).id;
                    else
                        error([dst ' contains ' trgName ', which is not a sync dir. Remove it first, then try again']);
                    end
                else
                    % Nothing there yet.
                    result = o.makeDir(trgName,'',dstInfo.id);
                    trgId = result.id;
                end
            end
            
            logUp = o.do('sync upload', dryRunStr ,src , trgId);
            logDown = o.do('sync download', dryRunStr,trgId ,src);
            result =cat(2,logUp,logDown);
        end
        
        
        function result = put(o,src,dst,overwrite)
            % Copy a file or directory to a destination on Google Drive.
            % INPUT
            % src = local file/dir
            % dst = target file/dir.
            % overwrite = [false]. Set to true to overwrite the
            %                   destination.
            % OUTPUT
            % log = log of the gdrive interaction
            %
            % EXAMPLES
            %  A directory can only be 'put' on Google Drive if it does not
            %  exist already (if you want to 'put' a directory repeatedly,
            %  then you should look at the 'sync' method).
            %
            % Use a trailing '/' to indicate that a src directory should be
            % copied into the dst (rather than replace it).
            % put('myDir','/docs/')  -> will create /docs/myDir
            % put('myFile','/docs') -> will create /docs/myFile.
            % put('myFile','/docs/myFile') -> will create /docs/myFile.
            % put('myFile','/docs/myFile',true) -> will update /docs/myFile.
            
            srcIsFile = exist(src,'file') ==2;
            if ~(srcIsFile || exist(src,'dir'))
                error([src ' does not exist. Nothing to copy?']);
            end
            if nargin <4
                overwrite = false;
            end
            
            [pth,file,ext] = fileparts(src);
            if isempty(pth) || strcmp(pth,'.')
                pth = pwd;
            end
            % Check on drive
            [dstInfo,dstList] = info(o,dst);
            
            if isempty(dstInfo.id)
                % dst does not exist yet. We want to create it..
                % file->new file
                % dir ->new dir
                trg = '';
                cmd = ['upload --name ' dstInfo.name];
                parent = [' --parent ' dstInfo.parents];
            else
                dstIsFile = ~strcmpi(dstInfo.mime,'application/vnd.google-apps.folder');
                if srcIsFile
                    if dstIsFile
                        % file->file
                        if overwrite
                            cmd  ='update';
                            trg = dstInfo.id;
                            parent= '';
                        else
                            error([ dst ' already exists. Set overwrite to true?'])
                        end
                    else
                        % file->dir
                        ix = strcmp([file ext],{dstList.name});
                        if any(ix)
                            if overwrite
                                cmd  ='update';
                                trg = dstList.id;
                                parent= '';
                            else
                                error([ dst '/' file ext ' already exists. Set overwrite to true?'])
                            end
                        else
                            cmd = 'upload';
                            trg= '';
                            parent = ['--parent  ' dstInfo.id];
                        end
                    end
                else
                    % src is dir. Most variants should use sync.
                    %Dir
                    if dstIsFile
                        %dir->file error
                        error([src ' is a dir but ' dst ' is a file. Not supported.']);
                    else
                        %dir->dir
                        if ismember(dst(end),[filesep ,'/'])
                            % Copy dir into the dst dir
                            % Check if the dir contains this dir already
                            ix = strcmp([file ext],{dstList.name});
                            if any(ix)
                                error([ src ' is a dir and ' dst '/' [file ext] ' is a dir. Use sync instead of copy'])
                            else
                                %OK
                                parent = ['--parent ' dstInfo.id];
                                trg = '';
                                cmd = 'upload';
                            end
                        else
                            error([ src ' is a dir and ' dst ' is a dir. Use sync instead of copy'])
                        end
                    end
                end
            end
            
            if srcIsFile
                recursive ='';
            else
                recursive = '--recursive';
            end
            result = o.do(cmd ,[recursive ' ' parent ' ' trg ],fullfile(pth,[file ext]));
        end
        
        
        function result = get(o,src,dst,overwrite)
            % Copy a file or directory from Google Drive to a local dir.
            % INPUT
            % src = Google file/dir
            % dst = local file/dir.
            % overwrite = [false]. Set to true to overwrite the
            %                   destination.
            % OUTPUT
            % log = log of the gdrive interaction
            %
            % EXAMPLES
            %
            % Directories are always created inside the dst directory.
            % So you probably dont want 
            % get('/docs','/docs') but get('/docs','/');
            %
            % get('/docs','/myDir/')  -> will create /myDir/docs
            % get('myFile','/docs') -> will create /docs/myFile.
            % get('myFile','/docs/myFile') -> will create /docs/myFile.
            % get('myFile','/docs/myFile',true) -> will update/overwrite /docs/myFile.
            %
            % There is currently no way to rename a dir on copy (i.e.
            % put('a','/b') will create /b/a (if b is a folder) or fail. It
            % will not create /b.
            
            if nargin <4
                overwrite = false;
            end
            
            dstIsFile = exist(dst,'file') ==2;
            dstIsDir = strcmpi(dst(end),'/');
            
            if dstIsFile && dstIsDir
                error([dst ' already exists and is a file. Remove it first to create a target directory']);
            end
            
           
            if (exist(dst,'file') || exist(dst,'dir') )&& ~overwrite
                error([dst ' already exists. Use overwrite=true to overwrite']);
            end
            
            [pth,file,ext] = fileparts(dst);
            if isempty(pth) || strcmp(pth,'.')
                pth = pwd;
            end
            
            % Check on drive
            [srcInfo,~] = info(o,src);
            if isempty(srcInfo.id)
                % src does not exist 
                error([src  ' does not exist. Nothing to get']);
            else
                srcIsFile = ~strcmpi(srcInfo.mime,'application/vnd.google-apps.folder');                
            end
            
            dstPath = fullfile(pth,[file ext]);
            if srcIsFile 
                recursive ='';
            else %src is a dir 
               if dstIsFile 
                    error(['Cannot copy dir ' src ' onto file ' dst ]);
               else                    
                    recursive = '--recursive';
                end
            end
            
            if overwrite
                force = '--force ';
            else
                force = '';
            end
            
            result = o.do('download',[force ' ' recursive ' --path ' dstPath ], srcInfo.id);
                
        end
        
        function result = list(o,str,includeTrash)
            % List all files on Google Drive that contain 'str'.
            % INPUT
            % str - The string for which to search in the filename
            % includeTrash - Set to true to also search in the trash
            %                   (Defaults to false)
            % OUPUT
            % result - struct with file information.
            
            if nargin <3
                includeTrash = false;
            end
            if includeTrash
                trQry = 'trashed=true and';
            else
                trQry = 'trashed=false and';
            end
            % Returns a listing
            result = o.do('list',['--query "' trQry ' name contains ''' str '''"']);
        end
        
        function [result,parentID] =dir(o,str)
            % Provide a directory listing.
            % INPUT
            % str - path of the directory.
            %           The top level on Google Drive is  '/'
            % OUTPUT
            % result - struct with information on the files and
            %               directories found in the 'src'
            % parentID - id of the 'str' directory (internal use).
            %
            % EXAMPLE
            % dir('/Share') % Provide information on all content of the
            %               Share directory at the top of the Google Drive.
            
            str = strrep(str,filesep,'/'); % Force unix
            if strcmpi(str(end),'/')
                str(end)=''; % Remove trailing /
            end
            dirs = strsplit(str,'/');
            for i=1:numel(dirs)
                if isempty(dirs{i}) || strcmp(dirs{i},'My Drive')
                    parentID = 'root';
                else
                    ix = strcmp(dirs{i},{result.name});
                    if ~any(ix)
                        if i==numel(dirs)
                            % Last element not found, maybe the caller just
                            % wants the parentID
                            result =struct('id','','name',dirs{i},'type','','size',0,'units','','created','');
                            break;
                        else
                            error(['sub dir ' dirs{i} ' does not exist in ' cat(2,dirs{1:i-1})]);
                        end
                    elseif i==numel(dirs) && strcmpi('bin',result(ix).type)
                        % Last element found and it is a file
                        result = result(ix);
                        break;
                    else
                        parentID = result(ix).id;
                    end
                end
                result = o.do('list',[' --query "trashed=false and ''' parentID ''' in parents"']);
            end
        end
        
        
    end
    
    %% Private Methods
    methods (Access=protected)
        
        function result = do(o,cmd,options,arg1,arg2)
            % Internal function that executes commands using the gdrive
            % executable , parses the results and returns them as a struct.
            % INPUT
            % cmd - one of the gdrive commands
            % options - options of the gdrive command
            % arg1 -  [Optional]. First argument to the command.
            % arg2 -  [Optional]. Second argument to the command.
            %
            % EXAMPLE
            % do('LIST','--query
            if nargin <5
                arg2 ='';
                if nargin <4
                    arg1 = '';
                    if nargin <3
                        options ='';
                    end
                end
            end
            
            completeCommand =sprintf('%s %s %s',o.gExeCommand, cmd,options);
            if ~isempty(arg1)
                completeCommand = [completeCommand ' "' arg1 '"'];
            end
            
            if ~isempty(arg2)
                completeCommand = [completeCommand ' "' arg2 '"'];
            end
            
            [status,output]= system(completeCommand);
            if (status~=0)
                disp('********Executing the following command ***********' );
                disp(completeCommand)
                disp('Generated output: ')
                disp(output)
                error('The gdrive command failed. See above for error')
            else
                result = gdrive.output2struct(output,cmd);
            end
        end
        
    end
    
    %% Statuc Methods
    % These methods parse the gdrive char outputs
    methods (Static, Access=protected)        
        function result = output2struct(output,src)
            % Pass gdrive output, including the header, and convert it into
            % a struct.
            %  output - the gdrive output
            % src     - which gdrive command does this output come from?
            % OUTPUT
            % result - a struct reprensenting the information in output
            %
            lines = strsplit(output,newline);
            out = cellfun(@isempty,lines);
            lines(out)=[];
            lines(1) = []; % Header
            nrElements = numel(lines);
            
            switch upper(src)
                case 'LIST'
                    %list output
                    base =struct('id','','name','','type','','size',0,'units','B','created','');
                    match = regexp(lines,'^(?<id>\S+)\s+(?<name>.+)\s+(?<type>\w{3,3})\s+(?<size>[\d\.]*)\s+(?<units>\w*)\s+(?<created>\d{4,4}-\d{2,2}-\d{2,2}\s\d{2,2}:\d{2,2}:\d{2,2})','names');
                    map = containers.Map({'size','created','other'},{@str2double,@datenum,@deblank});
                    result = gdrive.match2Struct(base,match,map,nrElements);
                case 'SYNC LIST'
                    base = struct('id','','name','','created',[]);
                    match = regexp(lines,'^(?<id>\S+)\s+(?<name>.+)\s+(?<name>.+)\s+(?<created>\d{4,4}-\d{2,2}-\d{2,2}\s\d{2,2}:\d{2,2}:\d{2,2})','names');
                    map = containers.Map({'created','other'},{@datenum,@deblank});
                    result = gdrive.match2Struct(base,match,map,nrElements);                    
                case 'ABOUT'
                    result = gdrive.lines2Struct(lines);
                case 'MKDIR'
                    tmp  = strsplit(output);
                    result.id = tmp{2};
                case 'INFO'
                    result = gdrive.lines2Struct(lines);
                case {'UPLOAD','UPDATE','SYNC UPLOAD','SYNC DOWNLOAD','DOWNLOAD'}
                    result.log = output;                    
                otherwise
                    error(['Converting gdrive command ' src ' output to a struct has not been implementd yet.']);
            end            
        end
        
        function result = lines2Struct(log)
            % A format returned by gdrive.exe contains tag:value pairs, one
            % on each line. Here we map those to struct.tag = value.
            % All tags are forced lower case. Extraneous spaces are removed
            % from values.
            tmp = cellfun(@(x) strsplit(x,':'),log,'UniformOutput',false);
            fields = cellfun(@(x)(strrep(lower(x{1}),' ','')),tmp,'uniformoutput',false);
            values = cellfun(@(x)(strip(x{2})),tmp,'uniformoutput',false);
            args = cell(1,2*numel(fields));
            [args{1:2:end}] = deal(fields{:});
            [args{2:2:end}] = deal(values{:});
            result =struct(args{:});
        end
        
        
        
        function result = match2Struct(base,match,map,nrElements)
            % A format returned by gdrive for listings. Each line is parsed
            % with a regexp and then converted to a struct here. 
            % The map container allows some postprocessing. See
            % output2Struct
            result = repmat(base,[nrElements 1]);
            for line = 1:nrElements
                fn = fieldnames(match{1});
                for f=1:numel(fn)
                    if isKey(map,fn{f})
                        fun = map(fn{f});
                    else
                        fun = [];
                    end
                    if isKey(map,'other')
                        otherFun  = map('other');
                    else
                        otherFun = [];
                    end
                    if ~isempty(fun)
                        value = fun(match{line}.(fn{f}));
                    elseif ~isempty(otherFun)
                        value = otherFun(match{line}.(fn{f}));
                    else
                        value  = match{line}.(fn{f});
                    end
                    result(line).(fn{f})= value;
                end
            end
        end
        
        function v = defaultExe
            % Determine the executable to use by default
            switch (computer)
                case 'PCWIN64'
                    v = 'gdrive-windows-x64.exe';
                case 'GLNXA64'
                    v= 'gdrive-linux-x64';
                case 'MACI64'
                    v = 'gdrive-osx-x64';
                otherwise
                    error(['No executable available for ' computer '. Please provide your own (from github.com/prasmussen/gdrive)'])
            end
        end

    end
    
end