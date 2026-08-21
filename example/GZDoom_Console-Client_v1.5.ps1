# ------------------------------------------------------------------------------------------------------------------------------------------------------
# This function searches for the latest version of a script with a given base name in a specified directory, loads it, and returns the file info object of the loaded script. 
# The expected naming convention for the scripts is BaseName_vX.X.ps1, where X.X represents the version number. If no matching scripts are found, an error is thrown.
# The -Path parameter is optional and defaults to the current directory if not provided.
function Get-LatestVersionedScript {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BaseName,

        [string[]]$Path = @(".", ".\lib")
    )

    foreach ($currentPath in $Path) {

        Write-Verbose "Searching for latest version of $BaseName in '$currentPath'"

        $pattern = "${BaseName}_v*.ps1"

        # Try versioned files first
        $scripts = Get-ChildItem -Path $currentPath -Filter $pattern -File -ErrorAction SilentlyContinue

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
        $baseFile = Join-Path $currentPath "${BaseName}.ps1"

        if (Test-Path $baseFile) {
            return Get-Item $baseFile
        }
    }

    throw "No matching versioned or base script found for '$BaseName' in paths: $($Path -join ', ')"
}

# Include GZDoom_PipeAPI_vX.X.ps1 for GZDoom-specific pipe communication functions and variables
try {

    Write-Host "Checking for latest version of GZDoom_PipeAPI"
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
# Windows IPC Named Pipe Client Definitions ---------------------------------
# Global Variables
# Pipe Parameters
$Global:NamedPipe_Client_AvailablePipeSelection_Filter = $true
$Global:NamedPipe_Client_AutomaticallySelectUniqueFilteredPipeServerName = $true
$Global:NamedPipe_Client_AvailablePipeSelection_NamePattern = '^[ZUG]ZD(_\d+)?$'
$Global:NamedPipe_Server_Name = 'Select' # can be replaced with actual pipe name if known/static
$Global:NamedPipe_Server_Process = 'Process'
$Global:NamedPipe_Server_ResponseDelay = 57 #milliseconds
$Global:NamedPipe_Server_ResponseTimeLimit = 5000 #milliseconds
# Pipe Communications Variables
$Global:NamedPipe_Client_ConnectedToServer = $false
$Global:NamedPipe_Server_Data = ''
$Global:NamedPipe_Server_Data_available = $false
$Global:NamedPipe_Client_Data = ''
$Global:NamedPipe_Client_Debug = $false
$Global:NamedPipe_Client_Debug = $true
#GZDoom API Parameters
$Global:GZDoom_PipeAPI_Debug = $true


# Startup ----------
Write-Host "`n[Startup]: Starting communications..." -ForegroundColor Green
NamedPipe_Client_Startup
# Communication Status After Startups
if ($Global:NamedPipe_Client_ConnectedToServer) {
    Write-Host "[Startup]: Named Pipe Client connected to ZDoom." -ForegroundColor Green
} else {
    Write-Host "[Startup]: Named Pipe Client not connected to ZDoom." -ForegroundColor Yellow
}
Write-Host "[Startup]: Starting main loop..." -ForegroundColor White
try {
    while ($true) {
		$userCommandPromptString = "[Main Loop]: Enter Command (exit"
		$debuggingActive = $Global:NamedPipe_Client_Debug -and $Global:GZDoom_PipeAPI_Debug
		$userCommandPromptString += "|debug=$($debuggingActive)"
		if ($Global:NamedPipe_Client_ConnectedToServer -ne $true) {
			Write-Host "[Main Loop]: The Pipe connection isn't made, but you can 'open' it at any time." -ForegroundColor Yellow
			$userCommandPromptString += "|open)> "
			
		} else {
			Write-Host "[Main Loop]: Since the Pipe is Connected, you can initiate a command to GZDoom." -ForegroundColor Green
			Write-Host "[Main Loop]: Type 'get' to emulate the 'GET <cvarName>' GZDoom console command, and update the local copy." -ForegroundColor Cyan
			$userCommandPromptString += "|get"
			Write-Host "[Main Loop]: Type 'set' to emulate the 'SET <cvarName> <cvarValue>' GZDoom console command, and update the local copy." -ForegroundColor Cyan
			$userCommandPromptString += "|set"
			Write-Host "[Main Loop]: Type 'console' to send a command verbatim to the GZDoom console, as if it was typed." -ForegroundColor Cyan
			$userCommandPromptString += "|console"
			Write-Host "[Main Loop]: Type 'peek' to check the streamReader buffer and report how many bytes of data are present." -ForegroundColor Cyan
			$userCommandPromptString += "|peek"
			Write-Host "[Main Loop]: Type 'read' to check the streamReader buffer and get any if present." -ForegroundColor Cyan
			$userCommandPromptString += "|read"
			Write-Host "[Main Loop]: Type 'pull' to send a request to the server and read a response." -ForegroundColor Cyan
			$userCommandPromptString += "|pull"
			Write-Host "[Main Loop]: Type 'close' to terminate the connection to the Named Pipe Server."
			$userCommandPromptString += "|close"
			$userCommandPromptString += ")> "
		}
		Write-Host -NoNewline $userCommandPromptString
		$cmd = Read-Host
		if ($cmd -ne '') {
			if ($cmd -eq 'exit') { 
				exit 1 
			} elseif ($cmd -eq 'debug') {
				$Global:NamedPipe_Server_Debug = -not $Global:NamedPipe_Server_Debug
				$Global:GZDoom_PipeAPI_Debug = -not $Global:GZDoom_PipeAPI_Debug
				$debuggingActive = $Global:NamedPipe_Server_Debug -and $Global:GZDoom_PipeAPI_Debug
				Write-Host "[debug] Debug Mode is now $($debuggingActive)" -ForegroundColor Green
			} elseif ($cmd -eq 'open') { 
				NamedPipe_Client_Startup 
			} elseif ($cmd -eq 'close') { 
				Write-Host "[Close]: Attempting to close pipe."
				NamedPipe_Client_CloseServerConnection
			} elseif ($cmd -eq 'get') { 
				Write-Host -NoNewline "[Enter CVAR Name to GET]: "
				$cvarNameToGet_host = Read-Host
				$cvarNameToGet = [string]$cvarNameToGet_host
				$remoteCVARvalueReadOK = GZDoom_PipeAPI_CVAR_GET -cvarName $cvarNameToGet
				if ($remoteCVARvalueReadOK) { 
					Write-Host "[GET]: GZDoom returned a value of '$($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String)' for '$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)'" -ForegroundColor Green
					if ($debuggingActive) { Write-Host "[GET]: Attempting to update local variable of the same name" }
					$localCVARvalueUpdated = GZDoom_PipeAPI_CMD_CVAR_Update_Local
					if ($localCVARvalueUpdated) {
						Write-Host "[GET]: Local Variable now matches Remote CVAR" -ForegroundColor Green
					} else {
						Write-Host "[GET]: Unable to match value of Local Variable to Remote CVAR" -ForegroundColor Red
					}
				} else {
					Write-Host "[GET]: Unable to obtain value for '$($cvarNameToGet)'" -ForegroundColor Red
				}
			} elseif ($cmd -eq 'set') { 
				Write-Host -NoNewline "[Enter CVAR Name to SET]: "
				$cvarNameToSet_host = Read-Host
				$cvarNameToSet = [string]$cvarNameToSet_host
				Write-Host "[SET] CVAR Name: $($cvarNameToSet)"
				Write-Host -NoNewline "[Enter CVAR Value to SET]: "
				$cvarValueToSet_host = Read-Host
				$cvarValueToSet = [string]$cvarValueToSet_host
				Write-Host "[SET] CVAR Value: $($cvarValueToSet)"
				$remoteCVARvalueWriteOK = GZDoom_PipeAPI_CVAR_SET -cvarName $cvarNameToGet -cvarValue $cvarValueToSet
				if ($remoteCVARvalueWriteOK) { 
					Write-Host "[SET]: GZDoom returned a value of '$($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String)' for '$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)'" -ForegroundColor Green
					if ($debuggingActive) { Write-Host "[SET]: Attempting to update local variable of the same name" }
					$localCVARvalueUpdated = GZDoom_PipeAPI_CMD_CVAR_Update_Local
					if ($localCVARvalueUpdated) {
						Write-Host "[SET]: Local Variable now matches Remote CVAR" -ForegroundColor Green
					} else {
						Write-Host "[SET]: Unable to match value of Local Variable to Remote CVAR" -ForegroundColor Red
					}
				} else {
					Write-Host "[SET]: Unable to obtain value for '$($cvarNameToGet)' to determine if SET was successful." -ForegroundColor Red
				}
			} elseif ($cmd -eq 'console') { 
				Write-Host -NoNewline "[Enter Console Command to Send]: "
				$commandStringToExecute = Read-Host
				Write-Host "[COMMAND]: Sending ' $($commandStringToExecute) ' to GZDoom..."
				$commandResult = GZDoom_PipeAPI_CONSOLE_COMMAND -commandString $commandStringToExecute
			} elseif ($cmd -eq 'peek') { 
				$bytes = NamedPipe_Client_PeekAtServer 
				Write-Host "[Peek]: $($bytes) available to read from Server."
			} elseif ($cmd -eq 'read') { 
				$Global:NamedPipe_Server_Data = NamedPipe_Client_ReadFromServer 
				Write-Host "[Read]: Data: $($Global:NamedPipe_Server_Data)"
			} elseif ($cmd -eq 'pull') {
				Write-Host -NoNewLine "[Pull]: Enter Request to Server> "
				$Global:NamedPipe_Client_Data = Read-Host
				$Global:NamedPipe_Server_Data = NamedPipe_Client_PullServerData -requestString $Global:NamedPipe_Client_Data
				Write-Host "[Pull]: Response: $($Global:NamedPipe_Server_Data)"
			} else {
				Write-Host "[Invalid Command]"
			}
			
		}
	}
}
catch {
	Write-Host "SERVER ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Terminate Pipe
    NamedPipe_Client_CloseServerConnection
    Write-Host "[Shutdown]: Pipe Disconnected"
}


if ($Global:NamedPipe_Client_ConnectedToServer) {
    Write-Host "[Startup]: Named Pipe Client connected to Server." -ForegroundColor Green
} else {
    Write-Host "[Startup]: Named Pipe Client not connected to Server." -ForegroundColor Yellow
}
Write-Host "[Startup]: Starting main loop..." -ForegroundColor White
try {
    while ($true) {
		$userCommandPromptString = "[Main Loop]: Enter Command (exit|"
		if ($Global:NamedPipe_Client_ConnectedToServer -ne $true) {
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
                    $Global:NamedPipe_Client_ConnectedToServer = NamedPipe_Client_ConnectToServer
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
				NamedPipe_Client_CloseServerConnection
				$Global:NamedPipe_Client_ConnectedToServer = $false				
			}
			elseif ($cmd -eq 'get') { 
				Write-Host -NoNewline "[Enter CVAR Name to GET]: "
				$cvarNameToGet = Read-Host
				if (GZDoom_PipeAPI_CVAR_GET -cvarName $cvarNameToGet) { GZDoom_PipeAPI_CMD_CVAR_Update_Local }
			}
			elseif ($cmd -eq 'set') { 
				Write-Host -NoNewline "[Enter CVAR Name to SET]: "
				$cvarNameToSet = Read-Host
				Write-Host -NoNewline "[Enter CVAR Value to SET]: "
				$cvarValueToSet = Read-Host                  
				if (GZDoom_PipeAPI_CVAR_SET -cvarName $cvarNameToGet -cvarValue $cvarValueToSet) { GZDoom_PipeAPI_CMD_CVAR_Update_Local }
			}
			elseif ($cmd -eq 'console') { 
				Write-Host -NoNewline "[Enter Console Command to Send]: "
				$commandStringToExecute = Read-Host
				$commandResult = GZDoom_PipeAPI_CONSOLE_COMMAND -commandString $commandStringToExecute
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

			
