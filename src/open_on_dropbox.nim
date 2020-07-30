# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.
import os, osproc, strutils, json
  
const DEFAULT_BROWSERS = ":x-www-browser:firefox:iceweasel:seamonkey:mozilla:epiphany:konqueror:chromium:chromium-browser:google-chrome"

type 
  UrlLink = object
   url*: string

proc find_browser(): string =
  let browser_var: string = os.getEnv("BROWSER", "")
  let browsers: seq[string] = (browser_var & DEFAULT_BROWSERS).split(":")

  for browser in browsers:
    echo "browser: " & browser
    if browser.existsFile():
      return browser
  
  raise newException(ValueError, "Couldn't find browser!")

proc open_browser_envvar() =
  let browser = find_browser()

  let args: seq[TaintedString] = commandLineParams()
  if args.len() != 1:
    raise newException(ValueError, "No Url Given!")

  let web_link = args[0]

  if  web_link.fileExists():
    echo "Found web file: " & web_link
  else:
    raise newException(ValueError, "Dropbox Web file not found!")

  let web_link_file = web_link.readFile()
  let web_link_json: JsonNode = parseJson(web_link_file)

  let web = to(web_link_json, UrlLink)
  echo "Using web link: " & web.url

  let (_, errC) = execCmdEx(browser & " " & web.url)

  if errC != 0:
    raise newException(ValueError, "Unknown error opening link")


when isMainModule:
  onUnhandledException =
    proc (errorMsg: string) =
      stderr.write("Error: ")
      stderr.writeLine(errorMsg)

  open_browser_envvar()
