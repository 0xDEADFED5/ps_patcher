# https://github.com/0xDEADFED5/ps_patcher
# Copyright (c) 2023 0xDEADFED5, MIT license
# PowerShell 5+ required (i think)
# FYI, this will read entire files into memory before patching them
class PatchInfo {
    # array of filenames to patch
    [string[]] $files
    # if true, filenames will be assumed to be relative and will be expanded to full path (default = true)
    [bool] $relative = $true
    # search and replace patterns, will be applied to every file in this entry
    # patterns looks like this: FFFF ?F -> 909090
    # spaces and case are ignored, ? matches any half-byte(nibble), ?? matches any whole byte
    # no wildcards (?) in the replace pattern (second half)
    [string[]] $patterns
    # if true, only patch the first match found, otherwise search the whole file for multiple matches (default = true)
    [bool] $first_only = $true
    # if true, save original file to *.bak before patching, prompt before overwrite (default = true)
    [bool] $backup = $true
    # if true and not all search patterns are found, confirm before saving (default = false)
    [bool] $warn_not_found = $false
}
#################################################################################################
#### Define patches here
#################################################################################################
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
#################################################################################################
##### Code starts here
#################################################################################################
$low_nibbles = @{ 
    [char]'0' = [byte]0x00
    [char]'1' = [byte]0x01
    [char]'2' = [byte]0x02
    [char]'3' = [byte]0x03
    [char]'4' = [byte]0x04
    [char]'5' = [byte]0x05
    [char]'6' = [byte]0x06
    [char]'7' = [byte]0x07
    [char]'8' = [byte]0x08
    [char]'9' = [byte]0x09
    [char]'A' = [byte]0x0A
    [char]'B' = [byte]0x0B
    [char]'C' = [byte]0x0C
    [char]'D' = [byte]0x0D
    [char]'E' = [byte]0x0E
    [char]'F' = [byte]0x0F
}
$high_nibbles = @{ 
    [char]'0' = [byte]0x00
    [char]'1' = [byte]0x10
    [char]'2' = [byte]0x20
    [char]'3' = [byte]0x30
    [char]'4' = [byte]0x40
    [char]'5' = [byte]0x50
    [char]'6' = [byte]0x60
    [char]'7' = [byte]0x70
    [char]'8' = [byte]0x80
    [char]'9' = [byte]0x90
    [char]'A' = [byte]0xA0
    [char]'B' = [byte]0xB0
    [char]'C' = [byte]0xC0
    [char]'D' = [byte]0xD0
    [char]'E' = [byte]0xE0
    [char]'F' = [byte]0xF0
}
function do_exit() {
    Write-Host 'Finished.  Press Enter to continue...'
    $null = $Host.UI.ReadLine()
    Exit
}
function abort([string]$msg) {
    Write-Host "Fatal error: $msg" -ForegroundColor red
    do_exit
}
function pattern_to_nibbles([string]$pattern) {
    $pattern = $pattern.Replace(' ', '').ToUpper()
    if ($pattern.Length % 2 -ne 0) {
        abort("Search pattern must have even length: '${pattern}'")
    }
    $search = [System.Array]::CreateInstance([byte], $pattern.Length)
    $high = $true
    $chars = $pattern.ToCharArray()
    for ($x = 0; $x -lt $chars.Count; $x++) {
        $c = $chars[$x]
        if ($high) {
            if ($chars[$x] -eq '?') {
                $search[$x] = 0xFF
            }
            else {
                if ($high_nibbles.ContainsKey($c)) {
                    $search[$x] = $high_nibbles[$c]
                }
                else {
                    abort("Bad search pattern: '${pattern}' !")
                }
            }
            $high = $false
        }
        else {
            if ($chars[$x] -eq '?') {
                $search[$x] = 0xFF
            }
            else {
                if ($low_nibbles.ContainsKey($c)) {
                    $search[$x] = $low_nibbles[$c]
                }
                else {
                    abort("Bad search pattern: '${pattern}' !")
                }
            }
            $high = $true
        }
    }
    $search
}
function pattern_to_bytes([string]$pattern) {
    $pattern = $pattern.Replace(' ', '').ToUpper()
    if ($pattern.Length % 2 -ne 0) {
        abort("Replace pattern must have even length: '${pattern}'")
    }
    [byte[]] -split ($pattern -replace '..', '0x$& ')
}
function search_bytes([byte[]][ref]$buffer, [byte[]][ref]$pattern, [bool]$first_only) {
    $indexes = New-Object Collections.Generic.List[Int32]
    $p_len = $pattern.Count / 2
    if ($p_len -gt $buffer.Count) {
        abort("Search pattern is longer than file!")
    }
    for ($x = 0; $x -le $buffer.Count - $p_len; $x++) {
        $found = $true
        $y = 0
        $x_temp = 0
        $hi = $true
        while ($found -and $y -ne $pattern.Count) {
            if ($pattern[$y] -eq 0xFF) {
                $hi = !$hi
                $y++
                continue
            }
            if ($hi) {
                $hi = $false
                if (($buffer[$x + $x_temp] -band 0xF0) -eq $pattern[$y]) {
                    $y++
                    continue
                }
                else {
                    $found = $false
                    break
                }
            }
            else {
                $hi = $true
                if (($buffer[$x + $x_temp] -band 0x0F) -eq $pattern[$y]) {
                    $y++
                    $x_temp++
                    continue
                }
                else {
                    $found = $false
                    break
                }
            }
        }
        if ($found) {
            $indexes.Add($x)
            if ($first_only) {
                break
            }
            # if input is '90 90 90 90 90' and pattern is '90 90'
            # i want to get 0,2 as result... not 0,1,2,3
            $x += ($p_len - 1)
        }
    }
    $indexes
}
function patch_buffer([byte[]][ref]$buffer, $index, [byte[]][ref]$patch) {
    if (($index + $patch.Count) -gt $buffer.Count) {
        abort("Attempting to patch past end of file!")
    }
    for ($x = 0; $x -lt $patch.Count; $x++) {
        $buffer[$index + $x] = $patch[$x]
    }
}
foreach ($p in $patches) {
    foreach ($f in $p.files) {
        $unique = 0
        $total = 0
        if ($p.relative) {
            $f = Join-Path $PSScriptRoot $f
        }
        if (!(Test-Path $f)) {
            Write-Host "File '${f}' not found, skipping ..." -ForegroundColor yellow
            continue
        }
        Write-Host "Loading file '${f}' ..."
        $buffer = [System.IO.File]::ReadAllBytes($f)
        Write-Host "File loaded." -ForegroundColor green
        foreach ($x in $p.patterns) {
            $s = $x -split '->'
            if ($s.Length -eq 2) {
                $search_p = $s[0].Trim()
                $search = pattern_to_nibbles($search_p)
                Write-Host "Searching '${f}' for pattern '${search_p}' ..."
                $i = search_bytes ([ref]$buffer) ([ref]$search) $p.first_only
                if ($i.Count -eq 0) {
                    Write-Host "Search pattern '${search_p}' not found in file '${f}', continuing ..." -ForegroundColor yellow
                    continue
                }
                else {
                    $unique++
                    $c = $i.Count
                    $total += $c
                    Write-Host "Search pattern '${search_p}' found ${c} times in file '${f}', continuing ..." -ForegroundColor green
                    $replace = pattern_to_bytes($s[1])
                    foreach ($z in $i) {
                        patch_buffer ([ref]$buffer) $z ([ref]$replace)
                    }
                }
            }
            else {
                abort("Must be single '->' in pattern!")
            }
        }
        if ($unique -ne 0) {
            if ($p.backup) {
                $backup = $f + '.bak'
                Write-Host "Backing up '${f}' to '${backup}'"
                if (Test-Path($backup)) {
                    $choice = Read-Host "File '${backup}' exists, overwrite? (y/N) "
                    if ($choice.ToLower() -eq 'y') {
                        Remove-Item -Path $backup
                        Rename-Item -Path $f -NewName $backup
                    }
                }
                else {
                    Rename-Item -Path $f -NewName $backup
                }
            }
            $p_total = $p.patterns.Count
            if ($p.warn_not_found -and ($unique -ne $p_total)) {
                $choice = Read-Host "Found (${unique} of ${p_total}) patches. ${total} total matches were patched, save file? (y/N)"
                if (!($choice.ToLower() -eq 'y')) {
                    if (!(Test-Path $f)) {
                        # shit, already renamed it
                        Write-Host "Restoring '${backup}' to '${f}'"
                        Rename-Item -Path $backup -NewName $f
                    }
                    continue
                }
            }
            else {
                Write-Host "Found (${unique} of ${p_total}) patches. ${total} total matches were patched."
            }
            [System.IO.File]::WriteAllBytes($f, $buffer)
            Write-Host "Changes saved to '${f}'." -ForegroundColor green
        }
        else {
            Write-Host "No search patterns matched in file '${f}' ..." -ForegroundColor yellow
        }
    }
}
do_exit