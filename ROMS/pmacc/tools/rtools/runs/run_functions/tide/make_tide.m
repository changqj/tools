function make_tide(tdlims,g_file,t_dir,out_dir)
% make_tide.m  12/6/2011  Parker MacCready
%
% This makes the tidal NetCDF forcing file for a ROMS 3.# simulation, and
% NOTE that you need the TPXO model files (tmd_toolbox/)
%------------------------------------------------------------------------
year = str2num(year);

ncfile_out = [out_dir,'tides.nc'];  % tide forcing file name

% get sizes and initialize the NetCDF file
% specify the constituents to use
c_data =  ['m2  ';'s2  ';'k1  ';'o1  '; ...
    'n2  ';'p1  ';'k2  ';'q1  '; ...
    '2n2 ';'mu2 ';'nu2 ';'l2  '; ...
    't2  ';'j1  ';'no1 ';'oo1 '; ...
    'rho1';'mf  ';'mm  ';'ssa ';'m4  '];
if 0
    np = size(c_data,1);
else
    % limit number of constituents, this is what is in TPXO7.1
    np = 8;
end
lon_rho = nc_varget(g_file,'lon_rho');
lat_rho = nc_varget(g_file,'lat_rho');
mask_rho = nc_varget(g_file,'mask_rho');
[ny,nx] = size(lon_rho);

my_mode = bitor ( nc_clobber_mode, nc_64bit_offset_mode );
disp(['*** creating ',ncfile_out,' ***']);
nc_create_empty ( ncfile_out, my_mode );
nc_padheader (ncfile_out , 20000 );
% add dimensions
nc_add_dimension( ncfile_out, 'tide_period', np);
nc_add_dimension( ncfile_out, 'xi_rho', nx);
nc_add_dimension( ncfile_out, 'eta_rho', ny);

% get constituent field and interpolate to grid
% get extracted amplitude and phases
t_file = [t_dir,'Extractions/tpxo7p2_180.mat'];
load(t_file);
x = Z.lon; y = Z.lat; mask = Z.mask;
% get set up to find constituent and nodal correction info
path(path,[t_dir,'/tmd_toolbox']);
% specify the tidal model to use
mod_name = 'tpxo7.2';
model = [t_dir,'/DATA7p2/Model_',mod_name];
for ii = 1:np
    cons = c_data(ii,:);
    cons_nb = deblank(cons);
    [junk,junk,ph,om,junk,junk] = ...
        constit(cons);
    disp([' Working on ',cons_nb,' period = ', ...
        num2str(2*pi/(3600*om)),' hours']);
    eval(['Eamp = E_',cons_nb,'.amp;']);
    eval(['Ephase = E_',cons_nb,'.phase;']);
    eval(['Cangle = C_',cons_nb,'.uincl;']);
    eval(['Cphase = C_',cons_nb,'.uphase;']);
    eval(['Cmax = C_',cons_nb,'.umaj;']);
    eval(['Cmin = C_',cons_nb,'.umin;']);
    % get nodal corrections centered on the middle
    % of the run time period, relative to day 48622 mjd (1/1/1992)
    trel = mean(tdlims) - datenum(1992,1,1);
    [pu,pf] = nodal(trel + 48622,cons);
    % interpolate to the model grid
    EC_list = {'Eamp','Ephase','Cangle','Cphase','Cmax','Cmin'};
    [X,Y] = meshgrid(x,y);
    for jj = 1:length(EC_list)
        eval(['this_in = ',EC_list{jj},';']);
        % first to a standard interpolation with NaN's
        this_out = NaN*lon_rho;
        this_in(~mask) = NaN;
        this_out = interp2(X,Y,this_in,lon_rho,lat_rho);
        % then go through row by row and extrapolate E-W
        nn = size(lon_rho,1);
        for kk = 1:nn
            this_row = this_out(kk,:);
            this_lon = lon_rho(kk,:);
            this_mask = ~isnan(this_row);
            if(length(this_row(this_mask))==1)
                %only 1 good element, but need 2 for interp1
                this_out_ex(kk,:) = this_row(this_mask);
            elseif(~isempty(this_row(this_mask)) && ...
                    length(this_row(this_mask))>1) %DAS added
                this_out_ex(kk,:) = interp1(this_lon(this_mask), ...
                    this_row(this_mask),this_lon,'nearest','extrap');
            else
                this_out_ex(kk,:) = this_out_ex(kk-1,:);
            end
        end
        eval([EC_list{jj},' = this_out_ex;']);
    end
    % and make final adjustments before writing to arrays
    tide_period(ii) = 2*pi/(3600*om); % hours
    tide_Eamp(ii,:,:) = pf*Eamp; % m
    tide_Ephase(ii,:,:) = Ephase - 180*ph/pi - 180*pu/pi; % deg
    tide_Cangle(ii,:,:) = Cangle; % deg
    tide_Cphase(ii,:,:) = Cphase - 180*ph/pi - 180*pu/pi; % deg
    tide_Cmax(ii,:,:) = pf*Cmax/100; % m s-1
    tide_Cmin(ii,:,:) = pf*Cmin/100; % m s-1
end

%make sure tide_period is a column vector
tide_period = tide_period(:);

% add the variables and write to them
varlist = {'tide_period','tide_Eamp','tide_Ephase', ...
    'tide_Cphase','tide_Cangle','tide_Cmax','tide_Cmin'};
for ii = 1:length(varlist)
    varname = varlist{ii};
    disp(['  making ',varname]);
    varstruct = Z_make_varstruct(varname);
    nc_addvar(ncfile_out,varstruct);
    % write the variables to the output file
    eval(['nc_varput(ncfile_out,varname,',varname,');']);
end

