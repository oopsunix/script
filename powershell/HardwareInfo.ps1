# 定义一个函数来将硬盘大小四舍五入到最接近的标准大小
function RoundToStandardSize([long]$size) {
    $gb = 1GB
    $tb = 1TB
    
    # 将大小转换为 TB
    $sizeInTB = $size / $tb
    
    # 标准大小列表（TB）
    $standardSizesTB = @(0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32, 64)
    
    # 找到最接近的标称大小
    $nearestSizeTB = $standardSizesTB | Sort-Object { [math]::Abs($_ - $sizeInTB) } | Select-Object -First 1
    
    # 四舍五入到最接近的标称大小
    $roundedSizeTB = [math]::Round($nearestSizeTB, 2)
    
    # 根据标称大小返回 GB 或 TB
    if ($roundedSizeTB -lt 1) {
        return "{0} GB" -f ($roundedSizeTB * 1024)
    } else {
        return "{0} TB" -f $roundedSizeTB
    }
}

# 获取系统信息
$systemInfo = Get-WmiObject -Class Win32_OperatingSystem
$processorInfo = Get-WmiObject -Class Win32_Processor
$memoryInfo = Get-WmiObject -Class Win32_PhysicalMemory
$diskInfo = Get-WmiObject -Class Win32_DiskDrive
$videoControllerInfo = Get-WmiObject -Class Win32_VideoController

# 输出操作系统信息
Write-Host "Operating System Information:"
Write-Host ("  OS Name:           {0}" -f $systemInfo.Name)
Write-Host ("  OS Version:        {0}" -f $systemInfo.Version)
Write-Host ("  OS Build:          {0}" -f $systemInfo.BuildNumber)

# 输出处理器信息
Write-Host "Processor Information:"
foreach ($processor in $processorInfo) {
    Write-Host ("  Processor Model:   {0}" -f $processor.Name)
}

# 输出内存信息
Write-Host "Memory Information:"
$totalMemory = 0
foreach ($memory in $memoryInfo) {
    $totalMemory += $memory.Capacity
    Write-Host ("  Memory Module:")
    Write-Host ("    Manufacturer:    {0}" -f $memory.Manufacturer)
    Write-Host ("    Product Name:    {0}" -f $memory.PartNumber)
    Write-Host ("    Capacity:        {0} MB" -f [math]::Round($memory.Capacity / 1MB, 2))
}
$memorySize = [math]::Round($totalMemory / 1GB, 2)
Write-Host ("  Total Physical RAM: {0} GB" -f $memorySize)

# 输出硬盘信息
Write-Host "Disk Information:"
foreach ($disk in $diskInfo) {
    Write-Host ("  Disk Model:        {0}" -f $disk.Model)
    $diskSizeGB = [math]::Round($disk.Size / 1GB, 2)
    $diskSizeTB = [math]::Round($disk.Size / 1TB, 2)
    
    # 使用 RoundToStandardSize 函数获取最接近的标准大小
    $standardSize = RoundToStandardSize $disk.Size
    
    Write-Host ("  Disk Size:         {0}" -f $standardSize)
    Write-Host ("  Interface Type:    {0}" -f $disk.InterfaceType)
}

# 输出显卡信息
Write-Host "Video Controller Information:"
foreach ($video in $videoControllerInfo) {
    Write-Host ("  Video Card:        {0}" -f $video.Name)
    # 使用 [double] 显式转换类型
    Write-Host ("  Video Memory:      {0} MB" -f [double]($video.AdapterRAM / 1MB))
}