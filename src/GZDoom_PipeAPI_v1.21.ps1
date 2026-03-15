# Include NamedPipe_Client_vX.X.ps1 in the same directory as this script to provide the PullPipe function for IPC with GZDoom.
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
try {

    $script = Get-LatestVersionedScript -BaseName "NamedPipe_Client"

    Write-Host "Loading $($script.Name)..."

    . $script.FullName

}
catch {

    Write-Host "Failed to load latest GZDoom_PipeAPI."
    Write-Host $_
    exit 1

}
NamedPipe_Client_loaded
# Pipe Parameters
$Global:NamedPipe_Server_Name = 'GZD'
$Global:NamedPipe_Server_Process = 'GZDoom'
$Global:NamedPipe_Server_ResponseDelay = 28 #milliseconds
$Global:NamedPipe_Server_ResponseTimeLimit = 5000 #milliseconds
$Global:NamedPipe_Server_Debug = $false
# Pipe Communications Variables
$Global:NamedPipe_Client_ConnectedToServer = $false
$Global:NamedPipe_Server_Data = ''
$Global:NamedPipe_Server_Data_available = $false
$Global:NamedPipe_Client_Data = ''
$Global:NamedPipe_Client_Debug = $false
#GZDoom API Parameters
$Global:GZDoom_PipeAPI_Debug = $false
# GZDoom API Communication variables
$Global:GZDoom_PipeAPI_CMD_CVAR_Name = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String = ''


Write-Host "[GZDoom_PipeAPI] variables registered" -ForegroundColor Green

Write-Host "[GZDoom_PipeAPI] Library Loading..." -ForegroundColor Gray


# ------------------------------------------------------------------------------------------------------------------------------------------------------
# GZDoom API ---------------------------------

# GZDoom External-Pipe API Console Command Formatting Functions (from externalpipe.h/.cpp) ----------------

$Global:GZDoom_PipeAPI_CMD_CVAR_Name = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String = ''
# In order to properly store and parse CVAR values, we use prefixes to indicate data types.
$Global:GZDoom_PipeAPI_CV_DataTypePrefix_String = 'CV_s'
$Global:GZDoom_PipeAPI_CV_DataTypePrefix_Integer = 'CV_i'
$Global:GZDoom_PipeAPI_CV_DataTypePrefix_FloatDouble = 'CV_f'
$Global:GZDoom_PipeAPI_CV_DataTypePrefix_Boolean = 'CV_b'
function GZDoom_PipeAPI_CMD_CVAR_Update_Local {
	
	# Check if the local CVAR variable exists; if not, create it.
	# This does not necessarily hold up accross programming languages, but in PowerShell we can use Get-Variable and Set-Variable.
	# So don't try and replicate this in C++ or other languages without similar "reflection capabilities".
	# But Python, JavaScript, and C# all have their own versions of reflection that can be used similarly.
	if (Test-Path "Variable:Global:$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)") {
		if ($Global:GZDoom_PipeAPI_Debug) {Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Local CVAR ' $Global:GZDoom_PipeAPI_CMD_CVAR_Name ' found in Script." }
	} else {
		if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: WARNING - Local CVAR ' $Global:GZDoom_PipeAPI_CMD_CVAR_Name ' is not declared explicitly in Script, but will attempt to create with initial value of ' $($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String) '" -ForegroundColor Yellow }
		Set-Variable -Name $Global:GZDoom_PipeAPI_CMD_CVAR_Name -Value $Global:GZDoom_PipeAPI_CMD_CVAR_Value_String -Scope Global
		$variableCreatedSuccessfully = Test-Path "Variable:Global:$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)"
		if ($variableCreatedSuccessfully) {
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Local CVAR ' $Global:GZDoom_PipeAPI_CMD_CVAR_Name ' created successfully." -ForegroundColor Green }
		} else {
			Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: FAULT - Failed to create local CVAR ' $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name '!" -ForegroundColor Red
		}
	}
	# Determine type based on prefix
	$regex_StringPrefix = '^' + $Global:GZDoom_PipeAPI_CV_DataTypePrefix_String
	$regex_IntegerPrefix = '^' + $Global:GZDoom_PipeAPI_CV_DataTypePrefix_Integer
	$regex_FloatPrefix = '^' + $Global:GZDoom_PipeAPI_CV_DataTypePrefix_FloatDouble
	$regex_BoolPrefix = '^' + $Global:GZDoom_PipeAPI_CV_DataTypePrefix_Boolean
	# Infer $Global:GZDoom_PipeAPI_CMD_CVAR_Value type based on prefix of $Global:GZDoom_PipeAPI_CMD_CVAR_Name
	switch -Regex ($Global:GZDoom_PipeAPI_CMD_CVAR_Name) {
		$regex_StringPrefix 	{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [string]$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String }
		$regex_IntegerPrefix 	{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value =    [int]$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String }
		$regex_FloatPrefix 		{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value =  [float]$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String }
		$regex_BoolPrefix 		{ 
									if     ($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String -eq 'true')	{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [bool]$True  }
									elseif ($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String -eq 'false')	{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [bool]$False }
									elseif ($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String -eq '1')		{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [bool]$True  }
									elseif ($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String -eq '0')		{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [bool]$False }
									else   																{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = [bool]$False }
								}
		default 				{ $Global:GZDoom_PipeAPI_CMD_CVAR_Value = $Global:GZDoom_PipeAPI_CMD_CVAR_Value_String } # fallback if no prefix match
	} # end of switch
	# Once the CVAR name and value are extracted and parsed, we can now update the local CVAR variable.
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Attempting to Set Final Target Value: $Global:GZDoom_PipeAPI_CMD_CVAR_Value" }
	Set-Variable -Name $Global:GZDoom_PipeAPI_CMD_CVAR_Name -Value $Global:GZDoom_PipeAPI_CMD_CVAR_Value -Scope Global
	# Validate
	$updated_value_of_target_variable = Get-Variable -Name $Global:GZDoom_PipeAPI_CMD_CVAR_Name -Scope Global -ValueOnly
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Updated value of target variable: $updated_value_of_target_variable" }
	$variable_updated_successfully = ($updated_value_of_target_variable -eq $Global:GZDoom_PipeAPI_CMD_CVAR_Value)
	if ($variable_updated_successfully) {
		if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Local Variable '$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)' is now '$($updated_value_of_target_variable)'" -ForegroundColor Green}
	} else { 
		Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: FAULT - Failed to Update Variable: $Global:GZDoom_PipeAPI_CMD_CVAR_Name ; Target Value: $Global:GZDoom_PipeAPI_CMD_CVAR_Value ; Actual Value: $updated_value_of_target_variable" -ForegroundColor Red
	}	
	return $variable_updated_successfully
}
Write-Host "[GZDoom_PipeAPI] GZDoom_PipeAPI_CMD_CVAR_Update_Local registered" -ForegroundColor Green

# Console Command: GET <cvar>
# Function Usage:
# if (GZDoom_PipeAPI_CVAR_GET -cvarName $name) { GZDoom_PipeAPI_CMD_CVAR_Update_Local }
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value_String = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Request_Format = 'GET cvarName'
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Success_Match_Pattern = '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$' # "<Name>" is "<Value>"
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_MissingName_String = 'GET: missing variable name. Proper usage is GET <cvar>'
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_TooManyArgs_String = 'GET: too many arguments. Proper usage is GET <cvar>'
$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_Undeclared_Match_Pattern = '^GET:\s"(.*?)"\sis\sunset$'
$Global:CMD_CVAR_GET_ReadData_SuccessResponse_Match_Pattern = '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$'
function GZDoom_PipeAPI_CVAR_GET {
    param (
        $cvarName
    )
    #Returns bool $true (remote value was read and local value updated successfully) or $false (remote value was not read or local value not updated)
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: CVAR: $cvarName" }
	# Prevent empty request
	if ($cvarName -eq $null) { 
		Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - null cvarName" -ForegroundColor Red
		return $false
	} elseif ($cvarName -eq "") {
		Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - empty cvarName" -ForegroundColor Red
		return $false
	}
	$cvarName = [string]$cvarName
	# Form Request String
	$GZDoom_PipeAPI_GET_Request_String = $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Request_Format
    $GZDoom_PipeAPI_GET_Request_String = $GZDoom_PipeAPI_GET_Request_String.Replace('cvarName', $cvarName)
    if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Request String: $GZDoom_PipeAPI_GET_Request_String" }
	# Pull Response from Server using Request
	$GZDoom_PipeAPI_GET_Response_String = NamedPipe_Client_PullServerData -requestString $GZDoom_PipeAPI_GET_Request_String
    $GZDoom_PipeAPI_GET_Server_Response_Available = ($GZDoom_PipeAPI_GET_Response_String.Length) -ne 0
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response String: $GZDoom_PipeAPI_GET_Response_String" }

    if (-not $GZDoom_PipeAPI_GET_Server_Response_Available) {
        Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - No response from GZDoom after CMD_CVAR_GET for ' $cvarName '" -ForegroundColor Red
		Write-Host "[GZDoom_PipeAPI_CVAR_GET]: CVAR '$cvarName' value not determined." -ForegroundColor Red
		return $false 
	}
    if ($GZDoom_PipeAPI_GET_Server_Response_Available) {
		# categorize response
		if ($GZDoom_PipeAPI_GET_Response_String -match $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Success_Match_Pattern) {
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response: GZDoom is reporting a current value of '$($Matches[2])' for remote CVAR '$($Matches[1])'" }
			$GZDoom_PipeAPI_CMD_CVAR_GET_Response_RegexPattern = $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Success_Match_Pattern					
			$GZDoom_PipeAPI_GET_Server_Response = 1  }
		elseif ($GZDoom_PipeAPI_GET_Response_String -match $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_Undeclared_Match_Pattern) { 
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response: GZDoom is reporting that remote CVAR '$($Matches[1])' is Undeclared/Unset." }
			$GZDoom_PipeAPI_GET_Server_Response = -1  }    
		elseif ($GZDoom_PipeAPI_GET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_MissingName_String)) { 
			$GZDoom_PipeAPI_GET_Server_Response = -2  }
		elseif ($GZDoom_PipeAPI_GET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Fault_TooManyArgs_String)) { 
			$GZDoom_PipeAPI_GET_Server_Response = -3  }
		else { 
			$GZDoom_PipeAPI_GET_Server_Response =  0 }
		if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response Code: $GZDoom_PipeAPI_GET_Server_Response" }
		# Not a GET response
		$GZDoom_Is_Not_Responding_To_GET = $GZDoom_PipeAPI_GET_Server_Response -eq 0
		if ($GZDoom_Is_Not_Responding_To_GET) {
			Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - Response from GZDoom is not a valid CMD_CVAR_GET response" -ForegroundColor Red
			Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - CVAR '$cvarName' value not determined." -ForegroundColor Red
			return $false 
		}
		# Response is a GET Fault
		$GZDoom_Is_Responding_To_GET_With_Fault = $GZDoom_PipeAPI_GET_Server_Response -le -1
		if ($GZDoom_Is_Responding_To_GET_With_Fault) {
			Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - $($response_line)" -ForegroundColor Red
			Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - CVAR '$cvarName' value not determined." -ForegroundColor Red
			return $false 
		}
		# Response is to a CMD_CVAR_GET
		$GZDoom_Is_Responding_To_GET_With_Name_And_Value = $GZDoom_PipeAPI_GET_Server_Response -ge 1
        if ( $GZDoom_Is_Responding_To_GET_With_Name_And_Value ) {
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Server is responding to a GET Request" }
			
			$null = $GZDoom_PipeAPI_GET_Response_String -match $GZDoom_PipeAPI_CMD_CVAR_GET_Response_RegexPattern
			$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name  = $Matches[1]
			$Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value_String = $Matches[2]
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response CVAR Name: $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name" }
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Response CVAR Value: $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value_String" }
			$GZDoom_GET_Response_CVAR_Name_Mismatch = ($cvarName -ne $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name)
			# Exit if names don't match
			if ($GZDoom_GET_Response_CVAR_Name_Mismatch) {
				Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - CVAR Name in response DOES NOT match CVAR Name sent!" -ForegroundColor Red
				Write-Host "[GZDoom_PipeAPI_CVAR_GET]: FAULT - CVAR '$cvarName' value not determined." -ForegroundColor Red
				return $false 
			}
			$GZDoom_GET_Response_CVAR_Name_Matches_Request = ($cvarName -eq $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name)
			if ($GZDoom_GET_Response_CVAR_Name_Matches_Request) {
				if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_GET]: Remote CVAR '$($Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name)' is '$($Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value_String)'." -ForegroundColor Green }
				# Update Values of local variables with values received from Server
				$Global:GZDoom_PipeAPI_CMD_CVAR_Name = $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Name
				$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String = $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Value_String
				return $true
			}
		}
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_PipeAPI_CVAR_GET registered" -ForegroundColor Green

# Console Command: SET <cvar> <value>
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value = ''
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Request_Format = 'SET cvarName cvarValue'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_Updated_Match_Pattern = '^\s*"(.*?)"\s+is\s+"(.*?)"\s*$'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_AlreadyUpToDate_Match_Pattern = '^\s*"(.*?)"\s+is already\s+"(.*?)"\s*$'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_MissingValue_String = 'SET: need variable value. Proper usage is SET <cvar> <value>'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_TooManyArgs_String = 'SET: too many arguments. Proper usage is SET <cvar> <value>'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_Malformed_String = 'SET: malformed command. Proper usage is SET <cvar> <value>'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_Uncreatable_String = 'SET: CVar could not be created'
$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_ReadOnly_String = 'SET: CVar is read-only'
function GZDoom_PipeAPI_CVAR_SET {
    param (
        $cvarName,
		$cvarValue
    )
    #Returns bool $true (remote value was updated successfully) or $false (remote value was not updated)
	if ($Global:GZDoom_PipeAPI_Debug) { 
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: [Raw function input] CVAR: $cvarName "
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: [Raw function input] Value: $cvarValue " }
	# Prevent empty request
	if ($cvarName -eq $null) { 
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - null cvarName" -ForegroundColor Red
		return $false
	} elseif ($cvarName -eq "") {
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - empty cvarName" -ForegroundColor Red
		return $false
	} elseif ($cvarValue -eq $null) {
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - null cvarValue" -ForegroundColor Red
		return $false
	} elseif ($cvarValue -eq "") {
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - empty cvarValue" -ForegroundColor Red
		return $false
	}
	$cvarName = [string]$cvarName
	$cvarValue = [string]$cvarValue
	if ($Global:GZDoom_PipeAPI_Debug) { 
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: [Function Input as String] CVAR: $cvarName "
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: [Function Input As String] Value: $cvarValue" }
	#keep in our back pocket, remove encapsulating doublequotes:
	#if ($commandPart.StartsWith('"') -and $commandPart.EndsWith('"')) {$commandPart = $commandPart.Substring(1, $commandPart.Length - 2)}
	# Form Request String
	$GZDoom_PipeAPI_SET_Request_String = $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Request_Format
    $GZDoom_PipeAPI_SET_Request_String = $GZDoom_PipeAPI_SET_Request_String.Replace('cvarName', $cvarName)
    $GZDoom_PipeAPI_SET_Request_String = $GZDoom_PipeAPI_SET_Request_String.Replace('cvarValue', $cvarValue)
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Request String: $GZDoom_PipeAPI_SET_Request_String" }
    # Pull Response from Server using Request
	$GZDoom_PipeAPI_SET_Response_String = NamedPipe_Client_PullServerData -requestString $GZDoom_PipeAPI_SET_Request_String
    $GZDoom_PipeAPI_SET_Server_Response_Available = ($GZDoom_PipeAPI_SET_Response_String.Length) -ne 0
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: [Raw] Response String: $GZDoom_PipeAPI_SET_Response_String" }
    if (-not $GZDoom_PipeAPI_SET_Server_Response_Available) {
        Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - No response from GZDoom after CMD_CVAR_SET for ' $cvarName '" -ForegroundColor Red
		Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red
		return $false 
	}
    if ($GZDoom_PipeAPI_SET_Server_Response_Available) {
		# categorize response
		if ($GZDoom_PipeAPI_SET_Response_String -match $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_Updated_Match_Pattern) { 
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response: GZDoom reports the value of remote CVAR '$($Matches[1])' has changed to a requested value '$($Matches[2])'." }
			$GZDoom_PipeAPI_CMD_CVAR_SET_Response_RegexPattern = $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_Updated_Match_Pattern
			$GZDoom_PipeAPI_SET_Server_Response = 1 }
		elseif ($GZDoom_PipeAPI_SET_Response_String -match $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_AlreadyUpToDate_Match_Pattern) { 
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response: GZDoom reports remote CVAR '$($Matches[1])' already had a requested value of '$($Matches[2])'."}
			$GZDoom_PipeAPI_CMD_CVAR_SET_Response_RegexPattern = $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Success_AlreadyUpToDate_Match_Pattern
			$GZDoom_PipeAPI_SET_Server_Response = 2 }
		elseif ($GZDoom_PipeAPI_SET_Response_String -match $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Success_Match_Pattern) {
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response: GZDoom is reporting a current value of '$($Matches[2])' for remote CVAR '$($Matches[1])'" }
			$GZDoom_PipeAPI_CMD_CVAR_SET_Response_RegexPattern = $Global:GZDoom_PipeAPI_CMD_CVAR_GET_Response_Success_Match_Pattern
			$GZDoom_PipeAPI_SET_Server_Response = 3 }
		elseif ($GZDoom_PipeAPI_SET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_MissingValue_String)) { 
			$GZDoom_PipeAPI_SET_Server_Response = -1 }
		elseif ($GZDoom_PipeAPI_SET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_TooManyArgs_String)) { 
			$GZDoom_PipeAPI_SET_Server_Response = -2 }
		elseif ($GZDoom_PipeAPI_SET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_Malformed_String)) { 
			$GZDoom_PipeAPI_SET_Server_Response = -3 }
		elseif ($GZDoom_PipeAPI_SET_Response_String.Contains($Global:GZDoom_PipeAPI_CMD_CVAR_SET_Response_Fault_Uncreatable_String)) { 
			$GZDoom_PipeAPI_SET_Server_Response = -4 }
		else { 
			$GZDoom_PipeAPI_SET_Server_Response =  0 }
		if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response Code: $GZDoom_PipeAPI_SET_Server_Response" }
		# Not a SET response
		$GZDoom_Is_Not_Responding_To_SET = $GZDoom_PipeAPI_SET_Server_Response -eq 0
		if ($GZDoom_Is_Not_Responding_To_SET) {
			Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response from GZDoom is not a valid CMD_CVAR_SET response" -ForegroundColor Red
			Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red
			return $false 
		}
		# Response is a SET Fault
		$GZDoom_Is_Responding_To_SET_With_Fault = $GZDoom_PipeAPI_SET_Server_Response -le -1
		if ($GZDoom_Is_Responding_To_SET_With_Fault) {
			Write-Host "[GZDoom_PipeAPI_CVAR_SET]: FAULT - $($response_line)" -ForegroundColor Red
			Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red
			return $false 
		}
		# Response is to a CMD_CVAR_SET
		$GZDoom_Is_Responding_To_SET_With_Name_And_Value = $GZDoom_PipeAPI_SET_Server_Response -ge 1
        if ( $GZDoom_Is_Responding_To_SET_With_Name_And_Value ) {
			$null = $GZDoom_PipeAPI_SET_Response_String -match $GZDoom_PipeAPI_CMD_CVAR_SET_Response_RegexPattern
			$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name  = $Matches[1]
			$Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value_String = $Matches[2]
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response CVAR Name: $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name" }
			$GZDoom_SET_Response_CVAR_Name_Mismatch = ($cvarName -ne $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name)
			# Exit if names don't match
			if ($GZDoom_SET_Response_CVAR_Name_Mismatch) {
				Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR Name in response DOES NOT match CVAR Name sent!" -ForegroundColor Red
				Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red
				return $false 
			}
			$GZDoom_SET_Response_CVAR_Name_Matches_Request = ($cvarName -eq $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name)
			if ($GZDoom_SET_Response_CVAR_Name_Matches_Request) {
				if ($Global:GZDoom_PipeAPI_Debug) { 
					Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response CVAR Name: $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name"
					Write-Host "[GZDoom_PipeAPI_CVAR_SET]: Response CVAR Value: $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value_String" }
				$GZDoom_SET_Response_CVAR_Value_Mismatch = ($cvarValue -ne $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value_String)
				if ($GZDoom_SET_Response_CVAR_Value_Mismatch) {
					Write-Host "[GZDoom_PipeAPI_CVAR_SET]: WARNING - CVAR Value in response DOES NOT match CVAR Value sent!" -ForegroundColor Yellow
					Write-Host "[GZDoom_PipeAPI_CVAR_SET]: CVAR '$cvarName' value not set to '$cvarValue'." -ForegroundColor Red 
					return $false
				}
				$GZDoom_SET_Response_CVAR_Value_Matches_Request = ($cvarValue -eq $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value_String)
				if ( $GZDoom_SET_Response_CVAR_Value_Matches_Request ) {					
					# Update Values of local variables with values received from Server
					$Global:GZDoom_PipeAPI_CMD_CVAR_Name = $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Name
					$Global:GZDoom_PipeAPI_CMD_CVAR_Value_String = $Global:GZDoom_PipeAPI_CMD_CVAR_SET_Value_String
					if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CMD_CVAR_Update_Local]: Remote CVAR '$($Global:GZDoom_PipeAPI_CMD_CVAR_Name)' is now '$($Global:GZDoom_PipeAPI_CMD_CVAR_Value_String)'" -ForegroundColor Green }
					return $true
				}
			}
		}
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_PipeAPI_CVAR_SET registered" -ForegroundColor Green


# Console Command: CMD <console command string>
$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String = ''
$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Request_Format = 'COMMAND consoleCommandString'
$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_RegEx = '^Executing Command:\s*".*?"'
$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_Prefix = 'Executing Command: '
$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_ParseResponse_RegEx = '^Executing Command:\s*"([^"]*)"'
#JST: change back to Prefix so that we can have a mixed set of single quotes and double quotes
function GZDoom_PipeAPI_CONSOLE_COMMAND {
    param (
        $commandString
    )
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Command: $($commandString)" }
	# Request format - Client: COMMAND <console command string> -> Server: Executing Command: "<console command string>"
		# Prevent empty request
	if ($commandString -eq $null) { 
		Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - null commandString" -ForegroundColor Red
		return $false
	} elseif ($commandString -eq "") {
		Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - empty commandString" -ForegroundColor Red
		return $false
	}
	$commandString = [string]$commandString
	$GZDoom_PipeAPI_CONSOLE_COMMAND_Request_String = $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Request_Format
    $GZDoom_PipeAPI_CONSOLE_COMMAND_Request_String = $GZDoom_PipeAPI_CONSOLE_COMMAND_Request_String.Replace('consoleCommandString', $commandString)
    if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Request String: $($GZDoom_PipeAPI_CONSOLE_COMMAND_Request_String)" }
	# Pull Response from Server using Request
	$GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String = NamedPipe_Client_PullServerData -requestString $GZDoom_PipeAPI_CONSOLE_COMMAND_Request_String	
    $GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response_Available = ($GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String.Length) -ne 0
	if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Response String: $($GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String)" }

    if (-not $GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response_Available) {
        Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - No response from GZDoom after CMD_CONSOLE_COMMAND for '$commandString'" -ForegroundColor Red
		return $false
    }
    if ($GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response_Available) {
		#if ($GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String -match $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_RegEx) { 
		if ($GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String.StartsWith($Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_Prefix)) { 
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Response: GZDoom executed a command, included" }
			$GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response = 1 }
		else {			
			$GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response = 0 }
		if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Response Code: $($GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response)" }
		# Not a COMMAND response
		$GZDoom_Is_Not_Responding_To_CONSOLE_COMMAND = $GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response -eq 0
		if ($GZDoom_Is_Not_Responding_To_CONSOLE_COMMAND) {
			Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - Response ' $($GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String) ' doesn't match format $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_RegEx." -ForegroundColor Red
			Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - Execution status unknown for command '$commandString'." -ForegroundColor Red
			return $false 
		}
		$GZDoom_Is_Responding_to_a_CONSOLE_COMMAND = $GZDoom_PipeAPI_CONSOLE_COMMAND_Server_Response -ge 1
        if ( $GZDoom_Is_Responding_to_a_CONSOLE_COMMAND ) {
			$prefixLength = $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_Response_Prefix.Length
			$commandPart = $GZDoom_PipeAPI_CONSOLE_COMMAND_Response_String.Substring($prefixLength)
			# remove surrounding quotes if present
			if ($commandPart.StartsWith('"') -and $commandPart.EndsWith('"')) {$commandPart = $commandPart.Substring(1, $commandPart.Length - 2)}
			$Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String = $commandPart
			if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Response Command String: $($Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String)" }
			$GZDoom_Is_Responding_to_a_different_CONSOLE_COMMAND = $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String -ne $commandString
			if ($GZDoom_Is_Responding_to_a_different_CONSOLE_COMMAND) {
				Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - Command Mismatch. Executed: $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String" -ForegroundColor Red
				Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: FAULT - Execution status unknown for command '$commandString'." -ForegroundColor Red
				return $false
			}
			$GZDoom_Is_Responding_to_this_CONSOLE_COMMAND = $Global:GZDoom_PipeAPI_CMD_CONSOLE_COMMAND_String -eq $commandString
			if ($GZDoom_Is_Responding_to_this_CONSOLE_COMMAND) {
				if ($Global:GZDoom_PipeAPI_Debug) { Write-Host "[GZDoom_PipeAPI_CONSOLE_COMMAND]: Server executed command: $commandString." -ForegroundColor Green }
				return $True
			}
		}
    }
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_PipeAPI_CONSOLE_COMMAND registered" -ForegroundColor Green
# GZDoom API Console Command Formatting Functions ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# GZDoom API ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# ------------------------------------------------------------------------------------------------------------------------------------------------------
function GZDoom_PipeAPI_loaded {
    Write-Host "[GZDoom_PipeAPI] GZDoom Pipe API library loaded and ready to use." -ForegroundColor Green
}
Write-Host "[GZDoom_PipeAPI] function GZDoom_PipeAPI_loaded registered" -ForegroundColor Green
Write-Host "[GZDoom_PipeAPI] Library Loaded." -ForegroundColor Gray
