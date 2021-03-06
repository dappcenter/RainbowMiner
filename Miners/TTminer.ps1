﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

if (-not $IsWindows -and -not $IsLinux) {return}

if ($IsLinux) {
    $Path = ".\Bin\NVIDIA-TTminer\TT-Miner"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v3.2.3b1-ttminer/TT-Miner-3.2.3-beta1.tar.xz"
} else {
    $Path = ".\Bin\NVIDIA-TTminer\TT-Miner.exe"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v3.2.3b1-ttminer/TT-Miner-3.2.3-beta1.zip"
}
$ManualUri = "https://bitcointalk.org/index.php?topic=5025783.0"
$Port = "333{0:d2}"
$DevFee = 1.0
$Cuda = "9.2"
$Version = "3.2.3-beta1"

if (-not $Global:DeviceCache.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "BLAKE2S"       ; MinMemGB = 2.4; NH = $false; Params = "-A BLAKE2S%CUDA% -coin KDA";     ExtendInterval = 2; Coins = @("KDA")} #Kadena
    #[PSCustomObject]@{MainAlgorithm = "EAGLESONG"     ; MinMemGB = 0.1; NH = $true;  Params = "-A EAGLESONG%CUDA% -coin CKB";   ExtendInterval = 2} #Eaglesong
    [PSCustomObject]@{MainAlgorithm = "ETHASH"        ; MinMemGB = 3;   NH = $true;  Params = "-A ETHASH%CUDA%"} #Ethash 
    [PSCustomObject]@{MainAlgorithm = "LYRA2V3"       ; MinMemGB = 1.5; NH = $false; Params = "-A LYRA2V3%CUDA%";               ExtendInterval = 2} #LYRA2V3
    [PSCustomObject]@{MainAlgorithm = "MTP"           ; MinMemGB = 5;   NH = $true;  Params = "-A MTP%CUDA%";                   ExtendInterval = 2} #MTP
    #[PSCustomObject]@{MainAlgorithm = "MTP-TCR"       ; MinMemGB = 5;   NH = $true;  Params = "-A MTP-TCR%CUDA%";               ExtendInterval = 2} #MTP-TCR
    [PSCustomObject]@{MainAlgorithm = "PROGPOW"       ; MinMemGB = 3;   NH = $false; Params = "-A PROGPOW%CUDA%";               ExtendInterval = 2} #ProgPoW (BCI)
    [PSCustomObject]@{MainAlgorithm = "PROGPOWSERO"   ; MinMemGB = 3;   NH = $false; Params = "-A PROGPOW092%CUDA% -coin SERO"; ExtendInterval = 2; Cuda ="10.1"} #ProgPoWSero (SERO)
    [PSCustomObject]@{MainAlgorithm = "PROGPOWH"      ; MinMemGB = 3;   NH = $false; Params = "-A PROGPOW092%CUDA% -coin HORA"; ExtendInterval = 2; Cuda ="10.1"} #ProgPoW (HORA)
    [PSCustomObject]@{MainAlgorithm = "PROGPOWZ"      ; MinMemGB = 3;   NH = $false; Params = "-A PROGPOWZ%CUDA%";              ExtendInterval = 2; Cuda ="10.1"} #ProgPoWZ (ZANO)
    [PSCustomObject]@{MainAlgorithm = "UBQHASH"       ; MinMemGB = 2.4; NH = $false; Params = "-A UBQHASH%CUDA%";               ExtendInterval = 2} #Ubqhash 
)

$CoinSymbols = @("EPIC","SERO","ZANO","ZCOIN","ETC","ETH","CLO","PIRL","MUSIC","EXP","ETP","CKB","KDA","VTC","UBQ","ERE")

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("NVIDIA")
        Name      = $Name
        Path      = $Path
        Port      = $Miner_Port
        Uri       = $Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
    }
    return
}

if (-not (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $Cuda -Warning $Name)) {return}

$Cuda = ""
if ($IsLinux) {
    $Cuda = "-$(if (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion "10.2") {"102"} elseif (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion "10.1") {"101"} elseif (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion "10.0") {"100"} else {"92"})"
}

$Global:DeviceCache.DevicesByTypes.NVIDIA | Select-Object Vendor, Model -Unique | ForEach-Object {
    $Device = $Global:DeviceCache.DevicesByTypes."$($_.Vendor)" | Where-Object Model -EQ $_.Model
    $Miner_Model = $_.Model

    $Commands | Where-Object {$_.Cuda -eq $null -or (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $_.Cuda -Warning "$($Name)-$($_.MainAlgorithm)")} | ForEach-Object {
        $First = $True
        $Algorithm_Norm_0 = Get-Algorithm $_.MainAlgorithm

        $MinMemGB = if ($Algorithm_Norm_0 -eq "Ethash") {if ($Pools.$Algorithm_Norm_0.EthDAGSize) {$Pools.$Algorithm_Norm_0.EthDAGSize} else {Get-EthDAGSize $Pools.$Algorithm_Norm_0.CoinSymbol}} else {$_.MinMemGB}

        $Miner_Device = $Device | Where-Object {Test-VRAM $_ $MinMemGB}
        
		foreach($Algorithm_Norm in @($Algorithm_Norm_0,"$($Algorithm_Norm_0)-$($Miner_Model)")) {
			if ($Pools.$Algorithm_Norm.Host -and ($_.NH -or $Pools.$Algorithm_Norm.Name -notmatch "Nicehash") -and (-not $_.Coins -or $_.Coins -icontains $Pools.$Algorithm_Norm.CoinSymbol) -and $Miner_Device) {
                if ($First) {
                    $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
                    $Miner_Name = (@($Name) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
                    $Miner_Protocol = "$(if ($Algorithm_Norm_0 -match "^(Ethash|ProgPow)" -and $Pools.$Algorithm_Norm_0.EthMode -eq "ethproxy" -and ($Pools.$Algorithm_Norm_0.Name -ne "MiningRigRentals" -or $Algorithm_Norm_0 -ne "ProgPow")) {"stratum1+$(if ($Pools.$Algorithm_Norm_0.SSL) {"ssl"} else {"tcp"})://"})"
                    $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ' '
                    $First = $False
                }
				$Pool_Port = if ($Pools.$Algorithm_Norm.Ports -ne $null -and $Pools.$Algorithm_Norm.Ports.GPU) {$Pools.$Algorithm_Norm.Ports.GPU} else {$Pools.$Algorithm_Norm.Port}
				[PSCustomObject]@{
					Name           = $Miner_Name
					DeviceName     = $Miner_Device.Name
					DeviceModel    = $Miner_Model
					Path           = $Path
					Arguments      = "--api-bind 127.0.0.1:`$mport -d $($DeviceIDsAll) -P $($Miner_Protocol)$($Pools.$Algorithm_Norm.User)$(if ($Pools.$Algorithm_Norm.Pass) {":$($Pools.$Algorithm_Norm.Pass)"})@$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -PRHRI 1 -nui $($_.Params -replace '%CUDA%',$Cuda)$(if ($_.Params -notmatch "-coin" -and $Pools.$Algorithm_Norm.CoinSymbol -and $CoinSymbols -icontains $Pools.$Algorithm_Norm.CoinSymbol) {" -coin $($Pools.$Algorithm_Norm.CoinSymbol)"})"
					HashRates      = [PSCustomObject]@{$Algorithm_Norm = $($Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".Week)}
					API            = "Claymore"
					Port           = $Miner_Port                
					Uri            = $Uri
                    FaultTolerance = $_.FaultTolerance
					ExtendInterval = $_.ExtendInterval
                    Penalty        = 0
					DevFee         = $DevFee
					ManualUri      = $ManualUri
                    StopCommand    = "Sleep 5"
                    Version        = $Version
                    PowerDraw      = 0
                    BaseName       = $Name
                    BaseAlgorithm  = $Algorithm_Norm_0
				}
			}
		}
    }
}