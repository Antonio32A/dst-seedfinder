import Base
import ../cli/args.bend as Args
import ../cli/config_file.bend as ConfigFile
import ./report.bend as SearchReport
import ./scan.bend as SearchScan
import ./cave_scan.bend as CaveScan

# `world find` on the shard the config was compiled for.
def run_query(+q: Args.Query, loaded: Result<&1, &1, U32 & String, ConfigFile.Loaded>) -> IO(Unit):
  match loaded:
    case Fail{failure}:
      SearchReport.fail_job(Args.query_json(q), failure)
    case Done{ConfigFile.Forest{config}}:
      SearchScan.run_query(q, Done{config})
    case Done{ConfigFile.Caves{config}}:
      CaveScan.run_query(q, config)
