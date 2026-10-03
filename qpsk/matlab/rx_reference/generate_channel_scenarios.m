function reports = generate_channel_scenarios()
%GENERATE_CHANNEL_SCENARIOS Generate preserved vectors for impairment tests.
profiles = {'baseline','phase_only','cfo_only','timing_offset', ...
    'clock_offset','awgn_20db','combined','timing_ppm_plus500', ...
    'timing_ppm_minus500','physical_lab','physical_stress'};
reports = cell(size(profiles));
for k=1:numel(profiles)
    fprintf('\n========== %s ==========\n',profiles{k});
    reports{k}=run_rx_chain_reference(profiles{k});
end
matlabDir=fileparts(fileparts(mfilename('fullpath')));
repoRoot=fileparts(matlabDir);
save(fullfile(repoRoot,'scenario_results','all_matlab_reports.mat'), ...
    'reports','profiles');
end
