Plugin.define do
  name    "rsense"
  version "0.1.0"
  file    "lib", "rsense"
  object  "Redcar::RSense"
  dependencies "core", ">0", "project", ">0", "Auto Completer", ">0", "redcar", ">0"
end