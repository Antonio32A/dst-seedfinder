import Base

def unreadable(+prefix: String, +path: String, failure: U32 & String) -> U32 & String:
  (code, reason) = failure
  (2, prefix ++ "cannot read " ++ path ++ ": " ++ reason)

def readable(+prefix: String, +path: String, result: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, String>:
  match result:
    case Fail{failure}:
      Fail{unreadable(prefix, path, failure)}
    case Done{text}:
      Done{text}

def read_result(got: File & Result<&1, &1, U32 & String, String>, +prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, String>):
  (file, result) = got
  do IO<Result<&1, &1, U32 & String, String>>:
    File.close(file)
    IO.pure(Result<&1, &1, U32 & String, String>, readable(prefix, path, result))

def read_opened(opened: Result<&1, &1, U32 & String, File>, +prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, String>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{unreadable(prefix, path, failure)})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, String>>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(file, 16777216)
        read_result(got, prefix, path)

# The text of a file, read with one call of at most 16 MB. A failure is (2, "<prefix>cannot read <path>: <reason>").
def read_text(+prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_opened(opened, prefix, path)

def byte_chunks(fuel: Nat, got: File & Result<&1, &1, U32 & String, List<&2, U32>>, chunks: List<&2, List<&2, U32>>) -> IO(File & List<&2, List<&2, U32>>):
  match fuel:
    case 0n:
      (file, result) = got
      IO.pure(File & List<&2, List<&2, U32>>, (file, chunks))
    case 1n+p:
      (file, result) = got
      match result:
        case Done{Con{byte, bytes}}:
          do IO<File & List<&2, List<&2, U32>>>:
            next : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 16777216)
            byte_chunks(p, next, (byte <> bytes) <> chunks)
        case _:
          IO.pure(File & List<&2, List<&2, U32>>, (file, chunks))

def bytes_closed(got: File & List<&2, List<&2, U32>>) -> IO(List<&2, U32>):
  (file, chunks) = got
  do IO<List<&2, U32>>:
    File.close(file)
    IO.pure(List<&2, U32>, List.concat(&2, U32, List.reverse(&2, List<&2, U32>, chunks)))

def bytes_opened(opened: Result<&1, &1, U32 & String, File>, +prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, List<&2, U32>>, Fail{unreadable(prefix, path, failure)})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, List<&2, U32>>>:
        got : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 16777216)
        chunks : File & List<&2, List<&2, U32>> <- byte_chunks(64n, got, Nil{})
        bytes : List<&2, U32> <- bytes_closed(chunks)
        IO.pure(Result<&1, &1, U32 & String, List<&2, U32>>, Done{bytes})

# The bytes of a file, read in chunks of 16 MB. A failure is (2, "<prefix>cannot read <path>: <reason>").
def read_bytes(+prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  do IO<Result<&1, &1, U32 & String, List<&2, U32>>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    bytes_opened(opened, prefix, path)

def unwritable(+prefix: String, +path: String, failure: U32 & String) -> U32 & String:
  (code, reason) = failure
  (2, prefix ++ "cannot write " ++ path ++ ": " ++ reason)

def writable(+prefix: String, +path: String, result: Result<&1, &1, U32 & String, Unit>) -> Result<&1, &1, U32 & String, Unit>:
  match result:
    case Fail{failure}:
      Fail{unwritable(prefix, path, failure)}
    case Done{done}:
      Done{done}

def write_closed(got: File & Result<&1, &1, U32 & String, Unit>, +prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  (file, result) = got
  do IO<Result<&1, &1, U32 & String, Unit>>:
    File.close(file)
    IO.pure(Result<&1, &1, U32 & String, Unit>, writable(prefix, path, result))

def write_opened(opened: Result<&1, &1, U32 & String, File>, bytes: List<&2, U32>, +prefix: String, +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{unwritable(prefix, path, failure)})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        got : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, bytes)
        write_closed(got, prefix, path)

# Writes the bytes to a file, replacing it. A failure is (2, "<prefix>cannot write <path>: <reason>").
def write_bytes(+prefix: String, +path: String, bytes: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_opened(opened, bytes, prefix, path)
