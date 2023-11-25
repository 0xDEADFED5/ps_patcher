# ps_patcher

A simple search and replace patcher in PowerShell.  
'?' in search patterns will match any nibble (half-byte).  
'??' will match any byte.  
Each patch definition can refer to multiple files and multiple search/replace patterns.  
I wrote this because I wanted an easy way to share small binary patches without shipping a patcher that gets flagged as malware.  

Notes: 

* Requires PowerShell 5+  
* Will load entire file into memory before patching  

Patches are defined at the top of the script.  

Like this:

```PowerShell
$patches = @(
    # example showing wildcard matches
    [PatchInfo]@{
        files    = @("example\test.bin")
        patterns = @("00 0? -> FFFF", "?C?C CC?? -> DEADFED5")
    }
    # example of patching multiple matches, and warning on not found
    [PatchInfo]@{
        files          = @("example\test2.bin")
        patterns       = @("FFFF -> CC CC", "88 -> 99")
        first_only     = $false
        warn_not_found = $true
    }
)
```

Read the script for more info.  

Right-click and 'Run with PowerShell' to run.