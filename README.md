# f3d_of_c3d_tool_library
A script to convert carbide 3d tool libraries to fusion 360 tool library for import.
Powershell command to get a test tool library:
convertfrom-C3d -Verbose | ConvertTo-Json -Depth 5 | out-file C:\temp\test-library.json -Force -Encoding ascii
