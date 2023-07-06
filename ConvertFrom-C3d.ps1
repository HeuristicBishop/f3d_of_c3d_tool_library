
function ConvertFrom-C3d {
    [CmdletBinding()]
    param (
        # Specifies a path to one or more locations.
        [Parameter(Position = 0,
            ParameterSetName = "ParameterSetName",
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Path to Carbide3d tools csv.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path = "$($env:LOCALAPPDATA)\Carbide 3D\Carbide Create\tools\*"
    )
    
    begin {
        
        # NOTE: c3d marks "deleted" tool libraries by starting the filename with a ~. So we ignore these files.
        $c3dLibraries = Get-ChildItem $Path | Where-Object name -NotMatch "^~" 
        $c3dCutters = ForEach($library in $c3dLibraries){
            $user, $machine, $material = $library.basename.split("+")
            Import-Csv $library.FullName | 
            Add-Member -Name "recipematerial" -Type NoteProperty -Value $material -PassThru |
            Add-Member -Name "recipemachine" -Type NoteProperty -Value $machine -PassThru
        }
        $sortedCutters = $c3dCutters | Group-Object model
        $fusionToolData = @()
    }
    
    process {

        foreach ($toolModel in $sortedCutters) {
            # NOTE: Some things are unfortunately unknowable given the c3d csv...so we're going with a best guess.
               $c3dCutter = $toolModel.group[0]

            if($c3dCutter.metric -eq "0"){ 
                $maybeOAL = 1.75
                $maybeLB = 1
                $maybeShoulderLength = [double]$c3dCutter.flutelength + .125
                $maybeShaftDiameter = if([double]$c3dCutter.diameter -ge .25 ){.25}else{.125}
            }
            # TODO: Check the $c3dCutter.metric property to handle mm/in correctly in the conversion.
            else {
                $maybeOAL = 1.75 * 25.4
                $maybeLB = 1 * 25.4
                $maybeShoulderLength = [double]$c3dCutter.flutelength + 3.175
                $maybeShaftDiameter = if([double]$c3dCutter.diameter -ge 3 ){6.35}else{3.175}
            }
            # NOTE: All of the amana tools that carbide supports are imperial with a quarter inch shank.
            if($c3dCutter.vendor -eq "Amana" ){$maybeShaftDiameter = 0.25}

            $convertedDescription = "$($c3dCutter.model)-$($c3dCutter.diameter)-$($c3dCutter.numFlutes)-$($c3dCutter.type)"
            Write-Verbose -Message ($c3dCutter | Out-String)

            # Begin creating the fusion JSON.
            $f3dTool = [PSCustomObject]@{
                BMC            = "carbide"
                GRADE          = "Mill Generic"
                description    = $convertedDescription
                geometry       = [ordered]@{
                    CSP               = $false
                    DC                = [double]$c3dCutter.diameter
                    # NOTE: We always spin clockwise.
                    HAND              = $true
                    LB                = $maybeLB #"length below holder" 
                    LCF               = [double]$c3dCutter.flutelength # "flute length"
                    NOF               = [double]$c3dCutter.numflutes
                    OAL               = $maybeOAL # "overall length"
                    SFDM              = $maybeShaftDiameter # "shaft diameter"
                    'shoulder-length' = $maybeShoulderLength # "shoulder length"
                }
                guid           = (New-Guid).Guid
                'post-process' = [ordered]@{
                    # Reasonable defaults according to...me :)
                    'break-control'      = $false
                    comment              = "$($c3dCutter.vendor)-$convertedDescription"
                    'diameter-offset'    = [int]$c3dCutter.number
                    'length-offset'      = [int]$c3dCutter.number
                    live                 = $true
                    # In fusion we keep this false because the machine intercepts tool changes anyway.
                    'manual-tool-change' = $false
                    number               = [int]$c3dCutter.number
                    turret               = 0
                }
                'product-id'   = $c3dCutter.model
                'product-link' = $c3dCutter.url
                'start-values' = @{
                    # TODO: Allow the import of all "material" libraries from c3d to feeds/speeds presets per tool.
                    presets = @(
                        foreach ($cutter in $toolModel.group){
                        # Note: Fusion really does not like a spindle speed of 0...so we make it 1.
                        if($cutter.rpm -eq "0"){$cutter.rpm = "1"}
                        [ordered]@{
                            description    = "Converted By HeuristicBishop"
                            f_n            = if($cutter.rpm -ne 0 ){ 402 / [double]$cutter.rpm}else{0} # Feed per revolution
                            f_z            = if($cutter.rpm -ne 0 ){[double]$cutter.'3dfeedrate' / ( [double]$cutter.rpm * [double]$cutter.numFlutes)}else{0} # Feed per tooth
                            guid           = (New-Guid).Guid
                            n              = [double]$cutter.rpm # Spindle speed
                            n_ramp         = [double]$cutter.rpm # Ramp spindle speeds
                            # TODO: Derive the name name from the imported csv.
                            name           = "$($cutter.recipematerial)-$($cutter.recipemachine)"
                            stepdown       = [double]$cutter.depth
                            # Stepover is defined in percent in c3d so we'll convert it here.
                            stepover       = ([double]$cutter.'3dstepover'/100 * [double]$cutter.diameter)
                            'tool-coolant' = "disabled"
                            'use-stepdown' = $true
                            'use-stepover' = $true
                            v_c            = ([double]$cutter.rpm * [double]$cutter.diameter * [Math]::PI)*.1 # Surface speed
                            v_f            = [double]$cutter.'3dfeedrate' # cutting feedrate
                            v_f_leadIn     = [double]$cutter.'3dfeedrate' # Lead in feed rate
                            v_f_leadOut    = [double]$cutter.'3dfeedrate' # Lead out feed rate
                            v_f_plunge     = [double]$cutter.plungerate # Plunge feedrate
                            v_f_ramp       = [double]$cutter.'3dfeedrate' # Ramp feedrate
                        }
                    }
                    )
                }
                # TODO: Make an enum for c3d type to fusion 360 type string.
                type           = switch ($c3dCutter.type ) {
                    "end" { "flat end mill" }
                    "ball" { "ball end mill" }
                    "engraver" { "chamfer mill" }
                    "vee" {"chamfer mill"}
                    default { "" }
                }
                unit           = if ([int]$c3dCutter.metric) {
                    "millimeters"
                }
                else { "inches" }
                vendor         = $c3dCutter.vendor
            }
            switch -Regex ($c3dCutter.number) {
                "503|504" { 
                    $f3dTool.geometry.DC = 0.125
                    $f3dTool.geometry.SFDM = 0.25
                    $f3dTool.type = "chamfer mill"
                 }
                 "602|603"{
                    $f3dTool.type = "face mill"
                    $f3dTool.geometry.RE = 0
                    $f3dTool.geometry.TA = 0
                }
            }
            # Switch for tacking on additional properties for specific mill types.
            switch ($f3dTool.type) {
                "chamfer mill" {
                    $f3dTool.geometry."tip-diameter" =  [double]$c3dCutter.cornerradius*2
                    $f3dTool.geometry.TA=[double]$c3dCutter.angle/2

                    if($c3dCutter.vendor -eq "Amana"){
                        $f3dTool.geometry."tip-diameter" = [double]$c3dCutter.diameter
                        $f3dTool.geometry.TA=[double]$c3dCutter.angle
                        $f3dTool.geometry.DC = 0.25
                    }
                    # TODO: Iterate through all presets if necessary.
                    #$f3dTool.'start-values'.presets[0].'use-stepdown' = $false
                    #$f3dTool.'start-values'.presets[0].'use-stepover' = $false

             }
            }
            Write-Verbose ($f3dTool | Out-String)
            $fusionToolData += $f3dTool
            #$f3dTool
        }
    }
    
    end {
        [ordered]@{
            data    = @($fusionToolData)
            version = 17
        }
    }
}