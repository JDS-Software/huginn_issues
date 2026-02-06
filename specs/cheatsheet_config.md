# Configuration Cheatsheet


| Category | Key | Type | Default | Description|
| --- | --- | --- | --- | --- |
| annotation | enabled | boolean | true | show virtual text annotations for open issues |
| | background | string | "#ffffff" | background color for annotation virtual text |
| | foreground | string | "#000000" | foreground color for annotation virtual text |
| plugin | issue_dir | string | issues | filepath (relative to config file) for the issue directory |
| index | key_length | integer | 16 (min 16, max 64) | length of index file names; increase if you have collisions |
| issue | open_after_create | boolean | false | open Issue.md in the editor after creating an issue |
| logging | enabled | boolean | false | saves the log buffer to logging.filepath if true |
| | filepath | string | ".huginnlog" | filepath to huginn's logging output |
| show | description_length | integer | 80 | maximum character length for issue descriptions in the show window |



