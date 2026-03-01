# GZDoom-PipeAPI
 - Windows Powershell library for interfacing with External-Pipe modded GZDoom
 - These give you access to the GET, SET, and COMMAND.
 - This is the heart of the data transfer
 - Requires WindowsIPCNamedPipeClient.ps1 as a library.

## Functions
 - GZDoom_API_CVAR_GET()
 - GZDoom_API_CVAR_GET()
 - GZDoom_API_CONSOLE_COMMAND()
 ### Helper Functions
 - GZDoom_API_ServerReadData_after_ClientWriteData
 - form_CMD_CVAR_GET_WritePipe_String
 - form_CMD_CVAR_SET_WritePipe_String
 - form_CMD_CONSOLE_COMMAND_WritePipe_String
 - is_CMD_CVAR_GET_Response_from_GZDoom
 - is_CMD_CVAR_SET_Response_from_GZDoom
 - is_CMD_CVAR_SET_Response_from_GZDoom_a_FaultCode
 - is_CMD_CONSOLE_COMMAND_Response_from_GZDoom
 - parse_CMD_CVAR_GET_Response_from_GZDoom
 - parse_CMD_CVAR_SET_Response_from_GZDoom
 - parse_CMD_CONSOLE_COMMAND_Response_from_GZDoom
