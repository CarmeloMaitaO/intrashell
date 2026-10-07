#[
  This file exists solely for helping LLMs get a quick summary of all the files
  within this repository.
]#
import std/[
  paths,
  dirs,
  syncio,
  json,
  strutils,
  sequtils,
  cmdline
]

type
  Repofile = ref object
    path: string
    content: string

proc getBasedir(params: seq[string]): Path =
  if params.len() >= 1:
    return Path(params[0])
  else:
    return Path("./")

proc getExclusionList(params: seq[string]): seq[Path] =
  result = @[]
  if params.len() >= 2:
    for index, path in params:
      if index != 0:
        result.add(Path(path))

proc list(dir: Path, exclusionList: seq[Path]): seq[Path] =
  result = @[]
  var
    aux: seq[Path] = @[]
    toExclude: bool = false
  for path in walkDirRec(dir):
    aux.add(path)
  for path in aux:
    toExclude = false
    for element in exclusionList:
      if path.isRelativeTo(element):
        toExclude = true
    if path in exclusionList:
      toExclude = true
    if not toExclude:
      result.add(path)

proc list(files: seq[Path]): seq[Repofile] =
  result = @[]
  for file in files:
    result.add(Repofile(
      path: $file,
      content: readFile($file)
    ))

proc list(files: seq[Repofile]): JsonNode =
  result = %*
    files

var
  parameters: seq[string] = commandLineParams()
  basedir: Path = getBasedir(parameters)
  exclusionList: seq[Path] = getExclusionList(parameters)
  tree: seq[Path] = list(basedir, exclusionList)
  fullTree: seq[Repofile] = list(tree)
  jsonTree: JsonNode = list(fullTree)

# echo $exclusionList
writeFile("summary.json", jsonTree.pretty())
