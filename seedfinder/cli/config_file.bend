import Base
import ../filters/config.bend as Config
import ./files.bend as Files

def compiled(text: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, Config.Config>:
  match text:
    case Fail{failure}:
      Fail{failure}
    case Done{json}:
      Config.config_of(json)

def load_config(path: Maybe<&2, String>) -> IO(Result<&1, &1, U32 & String, Config.Config>):
  match path:
    case None{}:
      IO.pure(Result<&1, &1, U32 & String, Config.Config>, Done{Config.Config{True{}, Nil{}, Nil{}, None{}, [Config.anything()]}})
    case Some{+file}:
      do IO<Result<&1, &1, U32 & String, Config.Config>>:
        text : Result<&1, &1, U32 & String, String> <- Files.read_text("config: ", file)
        IO.pure(Result<&1, &1, U32 & String, Config.Config>, compiled(text))
