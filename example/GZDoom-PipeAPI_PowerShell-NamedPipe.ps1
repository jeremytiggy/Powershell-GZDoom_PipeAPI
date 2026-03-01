# ------------------------------------------------------------------------------------------------------------------------------------------------------
# This function searches for the latest version of a script with a given base name in a specified directory, loads it, and returns the file info object of the loaded script. 
# The expected naming convention for the scripts is BaseName_vX.X.ps1, where X.X represents the version number. If no matching scripts are found, an error is thrown.
# The -Path parameter is optional and defaults to the current directory if not provided.
function Get-LatestVersionedScript {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BaseName,

        [string]$Path = "."
    )

    Write-Verbose "Searching for latest version of $BaseName in '$Path'"

    $pattern = "${BaseName}_v*.ps1"

    # Try versioned files first
    $scripts = Get-ChildItem -Path $Path -Filter $pattern -File -ErrorAction SilentlyContinue

    if ($scripts) {

        $latest = $scripts |
            Sort-Object {
                if ($_.Name -match 'v(\d+(\.\d+)+)') {
                    [version]$matches[1]
                }
                else {
                    [version]"0.0"
                }
            } -Descending |
            Select-Object -First 1

        return $latest
    }

    # Fallback to non-versioned file
    $baseFile = Join-Path $Path "${BaseName}.ps1"

    if (Test-Path $baseFile) {
        return Get-Item $baseFile
    }

    throw "No matching versioned or base script found for '$BaseName' in '$Path'."
}
# Include library for pipe communication functions and variables
# Include WindowsIPCNamedPipeClient_v1.0.ps1 pipe communication functions and variables
try {

    $script = Get-LatestVersionedScript -BaseName "WindowsIPCNamedPipeClient"

    Write-Host "Loading $($script.Name)..."

    . $script.FullName

}
catch {

    Write-Host "Failed to load latest WindowsIPCNamedPipeClient."
    Write-Host $_
    exit 1

}
WindowsIPCNamedPipeClient_loaded

# Include GZDoom_PipeAPI_vX.X.ps1 for GZDoom-specific pipe communication functions and variables
try {

    $script = Get-LatestVersionedScript -BaseName "GZDoom_PipeAPI"

    Write-Host "Loading $($script.Name)..."

    . $script.FullName

}
catch {

    Write-Host "Failed to load latest GZDoom_PipeAPI."
    Write-Host $_
    exit 1

}
GZDoom_PipeAPI_loaded


# Pipe Client Startup -------------------------------
$Global:pipeName = 'GZD'
function NamedPipeClientStartup {
    Write-Host "[Named Pipe Client Startup]: Pipe: $Global:pipeName" -ForegroundColor Cyan
    Write-Host "[Named Pipe Client Startup]: Connected: $Global:PipeConnected" -ForegroundColor Cyan
    $ProcessName = "GZDoom"
    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    {
        Write-Host "[Named Pipe Client Startup]: $ProcessName is running" -ForegroundColor Green
        if ($Global:PipeConnected -ne $true) {
            Write-Host "[Named Pipe Client Startup]: Would you like to open the pipe, or work offline?"
        }
    }
    else
    {
        Write-Host "[Named Pipe Client Startup]: $ProcessName is not running" -ForegroundColor Red
        if ($Global:PipeConnected -ne $true) {
            Write-Host "[Named Pipe Client Startup]: Would you like to attempt to open the pipe, or work offline?"
        }
        
    }
    if ($Global:PipeConnected -ne $true) {
        Write-Host -NoNewLine "[Named Pipe Client Startup] (open|offline|exit)> "
        $cmd = Read-Host
        if ($cmd -eq '') { exit 1 }
        if ($cmd -ne '') {
	        if ($cmd -eq 'exit') { exit 1 }
	        elseif ($cmd -eq 'open') { 
                # Open Pipe Connection
                try {
                    OpenPipe
                    $Global:PipeConnected = $true
                } catch {
                    Write-Host "[Named Pipe Client Startup]: ERROR. Failed to connect to pipe: $($_.Exception.Message)" -ForegroundColor Red
                    exit 1
                }        
            }
            elseif ($cmd -eq 'offline') { 
                Write-Host "[Named Pipe Client Startup]: Continuing in offline mode. No Named Pipe Communications initiated." -ForegroundColor Yellow
            }
	        else { 
                Write-Host '[Named Pipe Client Startup]: Exiting...' 
                exit 1
            }
        }
    }

}
# Pipe Client Startup ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Write-Host "`n[Startup]: Starting communications..." -ForegroundColor Green
$Global:PipeConnected = $false
$Global:pipeName = 'GZD'
NamedPipeClientStartup
# Communication Status After Startups
if ($Global:PipeConnected) {
    Write-Host "[Startup]: Named Pipe Client connected to Server." -ForegroundColor Green
} else {
    Write-Host "[Startup]: Named Pipe Client not connected to Server." -ForegroundColor Yellow
}
Write-Host "`n[Startup]: Starting main loop..." -ForegroundColor Green
try {
    while ($true) {
		$userCommandPromptString = "[Main Loop]: Enter Command (exit|"
		if ($Global:PipeConnected -ne $true) {
			Write-Host "[Main Loop]: The Pipe connection isn't made, but you can 'open' it at any time." -ForegroundColor Yellow
			$userCommandPromptString += "open)> "
			
		} else {
			# Write-Host "[Main Loop]: Since the Pipe is Open, you can initiate a PULL from the named pipe server." -ForegroundColor Green
			# $userCommandPromptString += "peek|read|pull|close)> "
			Write-Host "[Main Loop]: Since the Pipe is Open, you can make GET, SET, and CONSOLE requests to the API." -ForegroundColor Green
			$userCommandPromptString += "get|set|console|close)> "
		}
		Write-Host -NoNewline $userCommandPromptString
		$cmd = Read-Host
		if ($cmd -ne '') {
			if ($cmd -eq 'exit') { exit 1 }
			elseif ($cmd -eq 'open') { 
				#NamedPipeClientStartup 
				# Open Pipe Connection
                try {
                    OpenPipe
                    $Global:PipeConnected = $true
                } catch {
                    Write-Host "[Named Pipe Client Startup]: ERROR. Failed to connect to pipe: $($_.Exception.Message)" -ForegroundColor Red
                    exit 1
                }
			}
			# elseif ($cmd -eq 'peek') { PeekPipe }
			# elseif ($cmd -eq 'read') { ReadPipe }
			# elseif ($cmd -eq 'pull') {
			# 	Write-Host -NoNewLine "[Pipe Pull WriteData]: Enter string to send to named pipe server> "
			#	$Global:writeData = Read-Host
			#	PullPipe
			# }
			elseif ($cmd -eq 'close') { 
				if ($writer -ne $null) { 
					try { $Global:writer.Dispose() } 
					catch { } 
				}
				if ($pipe -ne $null) { 
					try { $Global:pipe.Dispose() } 
					catch { }
				}
				$Global:PipeConnected = $false				
			}
			elseif ($cmd -eq 'get') { 
                    Write-Host -NoNewline "[Enter CVAR Name to GET]: "
                    $cvarNameToGet = Read-Host
                    GZDoom_API_CVAR_GET -cvarName $cvarNameToGet
                }
                elseif ($cmd -eq 'set') { 
                    Write-Host -NoNewline "[Enter CVAR Name to SET]: "
                    $cvarNameToSet = Read-Host
                    Write-Host -NoNewline "[Enter CVAR Value to SET]: "
                    $cvarValueToSet = Read-Host
                    GZDoom_API_CVAR_SET -cvarName $cvarNameToSet -cvarValue $cvarValueToSet
                }
                elseif ($cmd -eq 'console') { 
                    Write-Host -NoNewline "[Enter Console Command to Send]: "
                    $Global:CMD_CONSOLE_COMMAND_String = Read-Host
                    GZDoom_API_CONSOLE_COMMAND -commandString $Global:CMD_CONSOLE_COMMAND_String
                }
			    else { Write-Host '[Invalid Command]' }
			
		}
	}
}
catch {
	Write-Host "SERVER ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Terminate Pipe
    if ($writer -ne $null) { 
        try { $Global:writer.Dispose() } catch { }
    }
    if ($pipe -ne $null) { 
        try { $Global:pipe.Dispose() } catch { }
    }
    Write-Host "[Shutdown]: Pipe Disconnected"
}

			
