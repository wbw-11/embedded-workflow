@{
    Name = 'GD32F407ZGT6'
    Type = 'GD32F4'
    FlashSize = '1MB'
    RamSize = '192KB'
    CrystalFreq = '24MHz'
    ReservedPins = @(13, 14, 15, 19, 20, 46, 47)
    ReservedDesc = @{
        13 = 'PA13/SWDIO (SWD 调试接口)'
        14 = 'PA14/SWCLK (SWD 调试接口)'
        15 = 'PA15/JTDI (JTAG 调试接口)'
        19 = 'PB3/JTDO (JTAG 调试接口)'
        20 = 'PB4/JNTRST (JTAG 调试接口)'
        46 = 'PC14/OSC32_IN (32.768kHz 晶振输入)'
        47 = 'PC15/OSC32_OUT (32.768kHz 晶振输出)'
    }
    AvailablePins = @(
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
        16, 17, 18, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
        64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79
    )
    DefaultUart = 'COM5'
    Toolchain = 'Keil ARM'
    ProjectExtension = '.uvprojx'
}

