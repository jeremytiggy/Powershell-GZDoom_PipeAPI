# Include WindowsIPCNamedClient_vX.X.ps1 in the same directory as this script to provide the PullPipe function for IPC with GZDoom.
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

Write-Host "[GZDoom_PipeAPI] Library Loading..." -ForegroundColor Gray


# ------------------------------------------------------------------------------------------------------------------------------------------------------
# GZDoom API ---------------------------------

# GZDoom API Console Command Formatting Functions (from externalpipe.h/.cpp) ----------------
$Global:CVAR_GET_Name = ''
$Global:CVAR_GET_Value = ''
$Global:CVAR_GET_Value_Raw = ''
$Global:CVAR_SET_Name = ''
$Global:CVAR_SET_Value = ''
$Global:CMD_CONSOLE_COMMAND_String = ''
$Global:CMD_CVAR_GET_WriteData_Format = 'GET cvarName'
# '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$'
$Global:CMD_CVAR_GET_ReadData_SuccessResponse_Match_Pattern = '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$'
$Global:CMD_CVAR_GET_ReadData_FaultResponse_MissingName_String = 'GET: missing variable name. Proper usage is GET <cvar>'
$Global:CMD_CVAR_GET_ReadData_FaultResponse_TooManyArgs_String = 'GET: too many arguments. Proper usage is GET <cvar>'
$Global:CMD_CVAR_GET_ReadData_FaultResponse_Undeclared_Match_Pattern = '^GET:\s"(.*?)"\sis\sunset$'
$Global:CMD_CVAR_SET_WriteData_Format = 'SET cvarName cvarValue'
$Global:CMD_CVAR_SET_ReadData_SuccessResponse_Updated_Match_Pattern = '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$'
$Global:CMD_CVAR_SET_ReadData_SuccessResponse_AlreadyUpToDate_Match_Pattern = '^\s*"(.*?)"\s+is already\s+"(.*?)"\s*$'
$Global:CMD_CVAR_SET_ReadData_FaultResponse_MissingValue_String = 'SET: need variable value. Proper usage is SET <cvar> <value>'
$Global:CMD_CVAR_SET_ReadData_FaultResponse_TooManyArgs_String = 'SET: too many arguments. Proper usage is SET <cvar> <value>'
$Global:CMD_CVAR_SET_ReadData_FaultResponse_Malformed_String = 'SET: malformed command. Proper usage is SET <cvar> <value>'
$Global:CMD_CVAR_SET_ReadData_FaultResponse_Uncreatable_String = 'SET: CVar could not be created'
$Global:CMD_CVAR_SET_ReadData_FaultResponse_ReadOnly_String = 'SET: CVar is read-only'
$Global:CMD_CONSOLE_COMMAND_WriteData_Format = 'COMMAND consoleCommandString'
$Global:CMD_CONSOLE_COMMAND_ReadData_RegEx = '^Executing Command:\s*".*?"'
$Global:CMD_CONSOLE_COMMAND_ParseResponse_RegEx = '^Executing Command:\s*"([^"]*)"'
$Global:CMD_CONSOLE_COMMAND_ReadData_Prefix = 'Executing Command: ' # Fix
# In order to properly store and parse CVAR values, we use prefixes to indicate data types.
$Global:CV_DataTypePrefix_String = 'CV_s'
$Global:CV_DataTypePrefix_Integer = 'CV_i'
$Global:CV_DataTypePrefix_FloatDouble = 'CV_f'
$Global:CV_DataTypePrefix_Boolean = 'CV_b'
Write-Host "[GZDoom_PipeAPI] variables registered" -ForegroundColor Green
function GZDoom_API_ServerReadData_after_ClientWriteData {
    param($client_WriteData)
    # Send the command to GZDoom via pipe, and wait for response
    # In the current version of this API, we expect that GZDoom will only be ever responding to one request at a time on the pipe.
    # In future versions, we may want to implement a request/response ID system to match responses to requests.
    # Or even just be able to batch multiple requests and responses. But at the moment, it's Script Send, GZDoom responds.
    # This will require a re-write if we add event based writing from GZDoom to the pipe.
    $Global:writeData = $client_WriteData
    $PullPipe_exitcode = (PullPipe)
    # Write-Host $PullPipe_Exitcode -ForegroundColor Gray
    $server_ReadData = $Global:readData
    return $server_ReadData
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_API_ServerReadData_after_ClientWriteData registered" -ForegroundColor Green
function form_CMD_CVAR_GET_WritePipe_String {
    param($cvarName)
    $writePipe_string = $Global:CMD_CVAR_GET_WriteData_Format
    $writePipe_string = $writePipe_string.Replace('cvarName', $cvarName)
    return $writePipe_string
}
Write-Host "[GZDoom_PipeAPI] function form_CMD_CVAR_GET_WritePipe_String registered" -ForegroundColor Green
function form_CMD_CVAR_SET_WritePipe_String {
    param($cvarName, $cvarValue)
    $writePipe_string = $Global:CMD_CVAR_SET_WriteData_Format
    $writePipe_string = $writePipe_string.Replace('cvarName', $cvarName)
    $writePipe_string = $writePipe_string.Replace('cvarValue', $cvarValue)
    return $writePipe_string
}
Write-Host "[GZDoom_PipeAPI] function form_CMD_CVAR_SET_WritePipe_String registered" -ForegroundColor Green
function form_CMD_CONSOLE_COMMAND_WritePipe_String {
    param($consoleCommandString)
    $writePipe_string = $Global:CMD_CONSOLE_COMMAND_WriteData_Format
    $writePipe_string = $writePipe_string.Replace('consoleCommandString', $consoleCommandString)
    return $writePipe_string
}
Write-Host "[GZDoom_PipeAPI] function form_CMD_CONSOLE_COMMAND_WritePipe_String registered" -ForegroundColor Green
function is_CMD_CVAR_GET_Response_from_GZDoom {
    param($response_line)
	if ($response_line -match $Global:CMD_CVAR_GET_ReadData_SuccessResponse_Match_Pattern) { return $True }
	if ($response_line -match $Global:CMD_CVAR_GET_ReadData_FaultResponse_Undeclared_Match_Pattern) { return $True }    
	if ($response_line.Contains($Global:CMD_CVAR_GET_ReadData_FaultResponse_MissingName_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_GET_ReadData_FaultResponse_TooManyArgs_String)) { return $True }
	return $False
}
Write-Host "[GZDoom_PipeAPI] function is_CMD_CVAR_GET_Response_from_GZDoom registered" -ForegroundColor Green
function is_CMD_CVAR_GET_Response_from_GZDoom_a_FaultCode {
    param($response_line)
    if ($response_line.Contains($Global:CMD_CVAR_GET_ReadData_FaultResponse_MissingName_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_GET_ReadData_FaultResponse_TooManyArgs_String)) { return $True }
    return $False
}
Write-Host "[GZDoom_PipeAPI] function is_CMD_CVAR_GET_Response_from_GZDoom_a_FaultCode registered" -ForegroundColor Green
function is_CMD_CVAR_SET_Response_from_GZDoom {
    param($response_line)
	# Valid responses to CMD_CVAR_SET are either the same as CMD_CVAR_GET, or an "is already" response.
    if ($response_line -match $Global:CMD_CVAR_SET_ReadData_SuccessResponse_Updated_Match_Pattern) { return $True }
    if ($response_line -match $Global:CMD_CVAR_SET_ReadData_SuccessResponse_AlreadyUpToDate_Match_Pattern) { return $True }
	if ($response_line -match $Global:CMD_CVAR_GET_ReadData_SuccessResponse_Match_Pattern) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_MissingValue_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_TooManyArgs_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_Malformed_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_Uncreatable_String)) { return $True }
    return $False
}
Write-Host "[GZDoom_PipeAPI] function is_CMD_CVAR_SET_Response_from_GZDoom registered" -ForegroundColor Green
function is_CMD_CVAR_SET_Response_from_GZDoom_a_FaultCode {
    param($response_line)
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_MissingValue_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_TooManyArgs_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_Malformed_String)) { return $True }
    if ($response_line.Contains($Global:CMD_CVAR_SET_ReadData_FaultResponse_Uncreatable_String)) { return $True }
    return $False
}
Write-Host "[GZDoom_PipeAPI] function is_CMD_CVAR_SET_Response_from_GZDoom_a_FaultCode" -ForegroundColor Green
function is_CMD_CONSOLE_COMMAND_Response_from_GZDoom {
    param($response_line)
    # Write-Host "[COMMAND]: Checking if data from GZDoom ($response_line) matches COMMAND response format ($Global:CMD_CONSOLE_COMMAND_ReadData_RegEx)." -ForegroundColor Gray
	if ($response_line -match $Global:CMD_CONSOLE_COMMAND_ReadData_RegEx) { 
		# Write-Host "[COMMAND]: $response_line matches format $Global:CMD_CONSOLE_COMMAND_ReadData_RegEx." -ForegroundColor Green
		return $True
	}

	Write-Host "[COMMAND]: $response_line doesn't match format $Global:CMD_CONSOLE_COMMAND_ReadData_RegEx." -ForegroundColor Yellow
	return $False
}
Write-Host "[GZDoom_PipeAPI] function is_CMD_CONSOLE_COMMAND_Response_from_GZDoom registered" -ForegroundColor Green
function parse_CMD_CVAR_GET_Response_from_GZDoom {
	param($response_line)
    
	# Check if response to a CMD_CVAR_GET; safeguard
	if ( is_CMD_CVAR_GET_Response_from_GZDoom -response_line $response_line ) {
        if ( is_CMD_CVAR_GET_Response_from_GZDoom_a_FaultCode -response_line $response_line ) {
            return "[GET]: Fault. $response_line"
        }
        # Using regular expressions, extract the <CVAR_name> and <CVAR_value> from the response.
        $matchResult = ($response_Line -match $Global:CMD_CVAR_GET_ReadData_SuccessResponse_Match_Pattern)
        $Global:CVAR_GET_Name  = $Matches[1]
		$Global:CVAR_GET_Value_String = $Matches[2]
        # Infer $Global:CVAR_GET_Value type based on prefix of $Global:CVAR_GET_Name
		switch -Regex ($Global:CVAR_GET_Name) {
			'^CV_s' { $Global:CVAR_GET_Value = [string]$Global:CVAR_GET_Value_String }
			'^CV_i' { $Global:CVAR_GET_Value = [int]$Global:CVAR_GET_Value_String }
			'^CV_f' { $Global:CVAR_GET_Value = [float]$Global:CVAR_GET_Value_String }
			'^CV_b' { 
						if ($Global:CVAR_GET_Value_String -eq 'true') { $Global:CVAR_GET_Value = [bool]$True }
						elseif ($Global:CVAR_GET_Value_String -eq 'false') { $Global:CVAR_GET_Value = [bool]$False }
						elseif ($Global:CVAR_GET_Value_String -eq '1') { $Global:CVAR_GET_Value = [bool]$True }
						elseif ($Global:CVAR_GET_Value_String -eq '0') { $Global:CVAR_GET_Value = [bool]$False }
						else {$Global:CVAR_GET_Value = [bool]$False }
					}
			default { $Global:CVAR_GET_Value = $Global:CVAR_GET_Value_String } # fallback if no prefix match
		} #end of switch
        
        # Once the CVAR name and value are extracted and parsed, we can now update the local CVAR variable.
        # Check if the local CVAR variable exists; if not, create it.
        # This does not necessarily hold up accross programming languages, but in PowerShell we can use Get-Variable and Set-Variable.
        # So don't try and replicate this in C++ or other languages without similar "reflection capabilities".
        # But Python, JavaScript, and C# all have their own versions of reflection that can be used similarly.
        if (Test-Path "Variable:Global:$($Global:CVAR_GET_Name)") {
			$localCVAR_Value = Get-Variable -Name $Global:CVAR_GET_Name -ValueOnly -Scope Global
		} else {
			Write-Host "[GET]: Local CVAR '$Global:CVAR_GET_Name' is not declared explicitly in Script, but will attempt to create."
			$localCVAR_Value = "[NEW]"
			Set-Variable -Name $Global:CVAR_GET_Name -Value $localCVAR_Value -Scope Global
		}
		Set-Variable -Name $Global:CVAR_GET_Name -Value $Global:CVAR_GET_Value -Scope Global
		$localCVAR_finalValue = Get-Variable -Name $Global:CVAR_GET_Name -ValueOnly -Scope Global
		return "[GET]: `$Global:$Global:CVAR_GET_Name : $localCVAR_Value >> $localCVAR_finalValue"
    }
	else {return "[GET]: No GET to parse]"}
	
}
Write-Host "[GZDoom_PipeAPI] function parse_CMD_CVAR_GET_Response_from_GZDoom registered" -ForegroundColor Green
function parse_CMD_CVAR_SET_Response_from_GZDoom {
	param($response_line)
    
	# Check if response to a CMD_CVAR_SET; safeguard
	if ( is_CMD_CVAR_SET_Response_from_GZDoom -response_line $response_line ) {
        if ( is_CMD_CVAR_SET_Response_from_GZDoom_a_FaultCode -response_line $response_line ) {
            return "[SET]: Fault. $response_line"
        }
        $response_CVAR_UPDATED = ($response_line -match $Global:CMD_CVAR_SET_ReadData_SuccessResponse_Updated_Match_Pattern)
        $response_CVAR_NOCHANGE = ($response_line -match $Global:CMD_CVAR_SET_ReadData_SuccessResponse_AlreadyUpToDate_Match_Pattern)
        if ($response_CVAR_UPDATED) {
            # Write-Host "[SET]: API reports that the CVAR value has been changed to the desired value." -ForegroundColor Green
            $match_pattern = $Global:CMD_CVAR_SET_ReadData_SuccessResponse_Updated_Match_Pattern
        }
        if ($response_CVAR_NOCHANGE) {
            # Write-Host "[SET]: API reports that the CVAR value was already set to the desired value." -ForegroundColor Yellow
            $match_pattern = $Global:CMD_CVAR_SET_ReadData_SuccessResponse_AlreadyUpToDate_Match_Pattern
        }
        # Using regular expressions, extract the <CVAR_name> and <CVAR_value> from the response.
        $matchResult = ($response_Line -match $match_pattern)
        $Global:CVAR_SET_Name  = $Matches[1]
		$Global:CVAR_SET_Value_String = $Matches[2]
        if ($response_CVAR_UPDATED) {
            # FUTURE: Account for response containing the previous value before the set
            # $Global:CVAR_SET_Value_String_Previous = $Matches[3]
        }

        # Check if the local CVAR variable exists; if not, create it.
        # This does not necessarily hold up accross programming languages, but in PowerShell we can use Get-Variable and Set-Variable.
        # So don't try and replicate this in C++ or other languages without similar "reflection capabilities".
        # But Python, JavaScript, and C# all have their own versions of reflection that can be used similarly.
        if (Test-Path "Variable:Global:$($Global:CVAR_SET_Name)") {
			# Write-Host "[SET]: Local CVAR ' $Global:CVAR_SET_Name ' found in Script."
		} else {
			Write-Host "[SET]: Local CVAR ' $Global:CVAR_SET_Name ' is not declared explicitly in Script, but will attempt to create." -ForegroundColor Yellow
			Set-Variable -Name $Global:CVAR_SET_Name -Value $Global:CVAR_SET_Value_String -Scope Global
            $variableCreatedSuccessfully = Test-Path "Variable:Global:$($Global:CVAR_SET_Name)"
            if ($variableCreatedSuccessfully) {
                #Write-Host "[SET]: Local CVAR ' $Global:CVAR_SET_Name ' created successfully." -ForegroundColor Green
            } else {
                Write-Host "[SET]: Failed to create local CVAR ' $Global:CVAR_SET_Name '!" -ForegroundColor Red
            }
		}
        # Determine type based on prefix
        # Infer $Global:CVAR_GET_Value type based on prefix of $Global:CVAR_GET_Name
		switch -Regex ($Global:CVAR_SET_Name) {
			'^CV_s' { $Global:CVAR_SET_Value = [string]$Global:CVAR_SET_Value_String }
			'^CV_i' { $Global:CVAR_SET_Value = [int]$Global:CVAR_SET_Value_String }
			'^CV_f' { $Global:CVAR_SET_Value = [float]$Global:CVAR_SET_Value_String }
			'^CV_b' { 
						if ($Global:CVAR_SET_Value_String -eq 'true') { $Global:CVAR_SET_Value = [bool]$True }
						elseif ($Global:CVAR_SET_Value_String -eq 'false') { $Global:CVAR_SET_Value = [bool]$False }
						elseif ($Global:CVAR_SET_Value_String -eq '1') { $Global:CVAR_SET_Value = [bool]$True }
						elseif ($Global:CVAR_SET_Value_String -eq '0') { $Global:CVAR_SET_Value = [bool]$False }
						else {$Global:CVAR_SET_Value = [bool]$False }
					}
			default { $Global:CVAR_SET_Value = $Global:CVAR_SET_Value_String } # fallback if no prefix match
		} # end of switch
        # Once the CVAR name and value are extracted and parsed, we can now update the local CVAR variable.
		Set-Variable -Name $Global:CVAR_SET_Name -Value $Global:CVAR_SET_Value -Scope Global
		
        # return "[SET]: Parsed Response - CVAR Name: $Global:CVAR_SET_Name , CVAR Value: $Global:CVAR_SET_Value_String"
        return ""
    }
	else {return "[SET]: No SET to parse]"}
}
Write-Host "[GZDoom_PipeAPI] function parse_CMD_CVAR_SET_Response_from_GZDoom registered" -ForegroundColor Green
function parse_CMD_CONSOLE_COMMAND_Response_from_GZDoom {
	param($response_line, $command_line)
	#Write-Host "[COMMAND]: Parsing response '$response_line' to Command '$command_line'"
	# Check if response to a CMD_CONSOLE_COMMAND; safeguard
	if ( is_CMD_CONSOLE_COMMAND_Response_from_GZDoom -response_line $response_line ) {
        # $commandExecuted = $response_line.Replace($Global:CMD_CONSOLE_COMMAND_ReadData_Prefix, '').Trim()
        $null = ($response_line -match $Global:CMD_CONSOLE_COMMAND_ParseResponse_RegEx)
        $commandExecuted = $Matches[1]
        $Global:CMD_CONSOLE_COMMAND_String = $commandExecuted

        # check if the command executed matches the command sent
        $responseMatches = $commandExecuted -eq $command_line
		if ($responseMatches) {
            return "[COMMAND]: Command '$command_line' Executed."
        }
        else {
            return "[COMMAND]: Mismatch. Command: $command_line , Executed: $commandExecuted"
        }
    }
	else {return "[COMMAND]: No Command Response to parse"}
}
Write-Host "[GZDoom_PipeAPI] function parse_CMD_CONSOLE_COMMAND_Response_from_GZDoom registered" -ForegroundColor Green
<# 
function GZDoom_API_CMD_GENERIC {
    param($commandData)
    $GZDoom_API_CMD_GENERIC_Client_WriteData = ( form_CMD_GENERIC_WritePipe_String -parameter1 $commandData )
    Write-Host "[GENERIC]: Sending to GZDoom: $GZDoom_API_GENERIC_Client_WriteData" -ForegroundColor Gray
    $GZDoom_API_GENERIC_Server_ReadData = ( GZDoom_API_ServerReadData_after_ClientWriteData -client_WriteData $GZDoom_API_GENERIC_Client_WriteData )
    Write-Host "[GENERIC]: Received from GZDoom: $GZDoom_API_GENERIC_Server_ReadData" -ForegroundColor Gray
    $GZDoom_API_GENERIC_Server_ReadData_Available = $GZDoom_API_GENERIC_Server_ReadData -ne ''

    if (-not $GZDoom_API_GENERIC_Server_ReadData_Available) {
        Write-Host "[GENERIC]: No response from GZDoom after CMD_GENERIC for '$cvarName'" -ForegroundColor Red
    }
    if ($GZDoom_API_GENERIC_Server_ReadData_Available) {
        Write-Host "[GENERIC]: Response available from GZDoom after CMD_GENERIC for '$commandData'" -ForegroundColor Green
        $GZDoom_Is_Responding_To_GENERIC = is_CMD_CVAR_GENERIC_Response_from_GZDoom -response_line $GZDoom_API_GENERIC_Server_ReadData
        if ( $GZDoom_Is_Responding_To_GENERIC ) {
			$GZDoom_GENERIC_Parse_Exitcode = parse_CMD_GENERIC_Response_from_GZDoom -response_line $GZDoom_API_GENERIC_Server_ReadData
            Write-Host ($GZDoom_GENERIC_Parse_Exitcode)
		} else {
            Write-Host "[GENERIC]: Response from GZDoom is not a valid CMD_GENERIC response" -ForegroundColor Red
        }
    }
}

#>
function GZDoom_API_CVAR_GET {
    param($cvarName)
    $GZDoom_API_GET_Client_WriteData = ( form_CMD_CVAR_GET_WritePipe_String -cvarName $cvarName )
    # Write-Host "[GET]: Polling GZDoom for value of ' $GZDoom_API_GET_Client_WriteData '" -ForegroundColor Gray
    $GZDoom_API_GET_Server_ReadData = ( GZDoom_API_ServerReadData_after_ClientWriteData -client_WriteData $GZDoom_API_GET_Client_WriteData )
    # Write-Host "[GET]: Received from GZDoom: $GZDoom_API_GET_Server_ReadData" -ForegroundColor Gray
    $GZDoom_API_GET_Server_ReadData_Available = $GZDoom_API_GET_Server_ReadData -ne ''

    if (-not $GZDoom_API_GET_Server_ReadData_Available) {
        Write-Host "[GET]: No response from GZDoom after CMD_CVAR_GET for ' $cvarName '" -ForegroundColor Red
    }
    if ($GZDoom_API_GET_Server_ReadData_Available) {
        # Write-Host "[GET]: Response available from GZDoom after CMD_CVAR_GET for '$cvarName'" -ForegroundColor Green
        $GZDoom_Is_Responding_To_GET = is_CMD_CVAR_GET_Response_from_GZDoom -response_line $GZDoom_API_GET_Server_ReadData
        if ( $GZDoom_Is_Responding_To_GET ) {
			$GZDoom_GET_Parse_Exitcode = parse_CMD_CVAR_GET_Response_from_GZDoom -response_line $GZDoom_API_GET_Server_ReadData
            Write-Host ($GZDoom_GET_Parse_Exitcode)
		} else {
            Write-Host "[GET]: Response from GZDoom is not a valid CMD_CVAR_GET response" -ForegroundColor Red
        }
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_API_CVAR_GET registered" -ForegroundColor Green
function GZDoom_API_CVAR_SET {
    param($cvarName, $cvarValue)
    $GZDoom_API_SET_Client_WriteData = ( form_CMD_CVAR_SET_WritePipe_String -cvarName $cvarName -cvarValue $cvarValue)
    # Write-Host "[SET]: Sending to GZDoom: $GZDoom_API_SET_Client_WriteData" -ForegroundColor Gray
    $GZDoom_API_SET_Server_ReadData = ( GZDoom_API_ServerReadData_after_ClientWriteData -client_WriteData $GZDoom_API_SET_Client_WriteData )
    # Write-Host "[SET]: Received from GZDoom: $GZDoom_API_SET_Server_ReadData" -ForegroundColor Gray
    $GZDoom_API_SET_Server_ReadData_Available = ($GZDoom_API_SET_Server_ReadData.Length) -ne 0
    # Write-Host ("[SET]: Data Available Flag: $GZDoom_API_SET_Server_ReadData_Available") -ForegroundColor Gray

    if (-not $GZDoom_API_SET_Server_ReadData_Available) {
        Write-Host "[SET]: No response from GZDoom after CMD_CVAR_SET for ' $cvarName '" -ForegroundColor Red
    }
    if ($GZDoom_API_SET_Server_ReadData_Available) {
        # Write-Host "[SET]: Response available from GZDoom after CMD_CVAR_SET for '$cvarName'" -ForegroundColor Green
        $GZDoom_Is_Responding_To_SET = (is_CMD_CVAR_SET_Response_from_GZDoom -response_line $GZDoom_API_SET_Server_ReadData)
        if ( $GZDoom_Is_Responding_To_SET ) {
			$GZDoom_SET_Parse_Exitcode = (parse_CMD_CVAR_SET_Response_from_GZDoom -response_line $GZDoom_API_SET_Server_ReadData)
            # Write-Host ($GZDoom_SET_Parse_Exitcode)
            $GZDoom_SET_Parsed_CVAR_Names_Match = ($cvarName -eq $Global:CVAR_SET_Name)
            if ( $GZDoom_SET_Parsed_CVAR_Names_Match ) {
                # Write-Host "[SET]: CVAR Name in response matches CVAR Name sent." -ForegroundColor Green
            } else {
                Write-Host "[SET]: CVAR Name in response DOES NOT match CVAR Name sent!" -ForegroundColor Red
            }
            $GZDoom_SET_Parsed_CVAR_Values_Match = ($cvarValue -eq $Global:CVAR_SET_Value_String)
            if ( $GZDoom_SET_Parsed_CVAR_Values_Match ) {
                # Write-Host "[SET]: CVAR Value in response matches CVAR Value sent." -ForegroundColor Green
            } else {
                Write-Host "[SET]: CVAR Value in response DOES NOT match CVAR Value sent!" -ForegroundColor Red
            }
            $GZDoom_SET_Success = $GZDoom_SET_Parsed_CVAR_Names_Match -and $GZDoom_SET_Parsed_CVAR_Values_Match
            if ( $GZDoom_SET_Success ) {
                Write-Host "[SET]: CVAR '$cvarName' value set to '$cvarValue' successfully." -ForegroundColor Green
            } else {
                Write-Host "[SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red
            }

		} else {
            Write-Host "[SET]: Response from GZDoom is not a valid CMD_CVAR_SET response" -ForegroundColor Red
        }
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_API_CVAR_GET registered" -ForegroundColor Green
function GZDoom_API_CONSOLE_COMMAND {
    param($commandString)
    # Current format - Client: COMMAND <console command string> -> Server: Executing Command: "<console command string>"
    $GZDoom_API_CONSOLE_COMMAND_Client_WriteData = ( form_CMD_CONSOLE_COMMAND_WritePipe_String -consoleCommandString $commandString)
    # Write-Host "[COMMAND]: Sending to GZDoom: $GZDoom_API_CONSOLE_COMMAND_Client_WriteData" -ForegroundColor Gray
    $GZDoom_API_CONSOLE_COMMAND_Server_ReadData = ( GZDoom_API_ServerReadData_after_ClientWriteData -client_WriteData $GZDoom_API_CONSOLE_COMMAND_Client_WriteData )
    # Write-Host "[COMMAND]: Received from GZDoom: $GZDoom_API_CONSOLE_COMMAND_Server_ReadData" -ForegroundColor Gray
    $GZDoom_API_CONSOLE_COMMAND_Server_ReadData_Available = ($GZDoom_API_CONSOLE_COMMAND_Server_ReadData.Length) -ne 0
    # Write-Host ("[COMMAND]: Data Available Flag: $GZDoom_API_CONSOLE_COMMAND_Server_ReadData_Available") -ForegroundColor Gray

    if (-not $GZDoom_API_CONSOLE_COMMAND_Server_ReadData_Available) {
        Write-Host "[COMMAND]: No response from GZDoom after CMD_CONSOLE_COMMAND for '$commandString'" -ForegroundColor Red
    }
    if ($GZDoom_API_CONSOLE_COMMAND_Server_ReadData_Available) {
        # Write-Host "[COMMAND]: Response available from GZDoom after CMD_CONSOLE_COMMAND for '$commandString'" -ForegroundColor Green
        $GZDoom_Is_Responding_To_CONSOLE_COMMAND = (is_CMD_CONSOLE_COMMAND_Response_from_GZDoom -response_line $GZDoom_API_CONSOLE_COMMAND_Server_ReadData)
        if ( $GZDoom_Is_Responding_To_CONSOLE_COMMAND ) {
			$GZDoom_CONSOLE_COMMAND_Parse_Exitcode = (parse_CMD_CONSOLE_COMMAND_Response_from_GZDoom -response_line $GZDoom_API_CONSOLE_COMMAND_Server_ReadData -command_line $commandString)
            Write-Host ($GZDoom_CONSOLE_COMMAND_Parse_Exitcode)
		} else {
            Write-Host "[COMMAND]: Response from GZDoom is not a valid CMD_CONSOLE_COMMAND response" -ForegroundColor Red
        }
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_API_CONSOLE_COMMAND registered" -ForegroundColor Green
# GZDoom API Console Command Formatting Functions ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# GZDoom API ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# ------------------------------------------------------------------------------------------------------------------------------------------------------
function GZDoom_PipeAPI_loaded {
    Write-Host "[GZDoom_PipeAPI] GZDoom Pipe API library loaded and ready to use." -ForegroundColor Green
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_PipeAPI_Test registered" -ForegroundColor Green
Write-Host "[GZDoom_PipeAPI] Library Loaded." -ForegroundColor Gray
