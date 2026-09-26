import Base
import ../filters/config.bend as CF
import ./files.bend as FL

def compiled(text: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, CF.Config>:
  match text:
    case Fail{failure}:
      Fail{failure}
    case Done{json}:
      CF.config_of(json)

def load_config(path: Maybe<&2, String>) -> IO(Result<&1, &1, U32 & String, CF.Config>):
  match path:
    case None{}:
      IO.pure(Result<&1, &1, U32 & String, CF.Config>, Done{CF.Config{True{}, Nil{}, Nil{}, None{}, [CF.anything()]}})
    case Some{+file}:
      do IO<Result<&1, &1, U32 & String, CF.Config>>:
        text : Result<&1, &1, U32 & String, String> <- FL.read_text("config: ", file)
        IO.pure(Result<&1, &1, U32 & String, CF.Config>, compiled(text))
