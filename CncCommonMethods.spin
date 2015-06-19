DAT programName         byte "CncCommonMethods", 0
CON
{{      

}}
{
  ******* Private Notes *******
  OLED_DriverDemo2140820a is a good starting point in
  my attempt to modify the code.
  20a Appears to work correctly.
  15f OLED and shift registers appear to work.
  15g Start changing OLED control pins to '595 channels.
  15g Works with pins but not '595 channels.
  15k Works with both pins and '595 channels.
  15l Remove I/O pin redundancy in child object. Still works.
  15m Start adding SD card support.
  Change name from "OledDriverDemoScratch150415n" to "CncCommonMethods150415a."
  16a Okay so far.
  16b "FitBitmap8" appears to work.
  16c Still works.
  16d Try to get single bit control of bitmap moves.
  16d Previous code still works.
  16e Tried new parts and it failed miserably.
  16f Part of bitmap looks like it's being placed too low.
  16g "FitBitmap" appears to work.
  18c Abandon 18b.
  20a There's something wrong with the way the bitmaps are displayed.
  20a Much better. Part of the bitmap isn't OR'ed correctly.
  20d Appears to work.
  20e Works better. Part of bitmap is scrolled when it shouldn't be.
  21a The inverted block appears to kind of work. One problem is the old block
  doesn't get restored before a new block is inverted.
  21b Try to restore previous block before inverting new block.
  21b I'm still having trouble with the way the inverted blocks are done.
  I think a big part of the problem is the way the top object continually changes the
  block coordinates so the values saved as the previous block's coordinates don't
  always match the coordinates used in the inversion.
  22c This kind of works. The partial bytes don't appear to work correctly.
  22d Something is wrong with the way the block height and extra bits are calculated.
  The extra bits added together don't match the block height.
  The debug display is working reasonably well.
  22f Remove pauses and a lot of debug statements.
  22f Works just about the way I want it to.
  Change name from "CncCommonMethods150426a" to "CncCommonMethods."
  
}  
CON

  _clkmode = xtal1 + pll16x                           
  _xinfreq = 5_000_000

  CLK_FREQ = ((_clkmode - xtal1) >> 6) * _xinfreq
  MS_001   = CLK_FREQ / 1_000
  US_001   = CLK_FREQ / 1_000_000

  SCALED_MULTIPLIER = 1000

  QUOTE = 34
  NUMBER_OF_SD_INSTANCES = Header#NUMBER_OF_SD_INSTANCES
  
OBJ

  Header : "HeaderCnc"
  Pst : "Parallax Serial TerminalDat"
  Format : "StrFmt"
  Sd[2]: "SdSmall" 
  Spi : "OledSpi" 
  'Num : "Numbers"
   
VAR


  'long lastRefreshTime, refreshInterval
  long oledStack[Header#MONITOR_OLED_STACK_SIZE]
  long sdErrorNumber, sdErrorString, sdTryCount
  long filePosition[Header#NUMBER_OF_SD_INSTANCES]
  long globalMultiplier, globalDecPoints
  long oledLabelPtr, oledDataPtrPtr, oledDataQuantity ' keep together and in order
  long shiftRegisterOutput, shiftRegisterInput
  'long adcData[8]
  'long debugSpi[16], extraDebug[16]
  long configPtr
  
  byte sdMountFlag[Header#NUMBER_OF_SD_INSTANCES]
  byte endFlag
  'byte configData[Header#CONFIG_SIZE]
  byte sdFlag
  byte tstr[32]
  byte activeScrollRow
  
  
DAT

designFileIndex         long -1             
targetInvertFlag        long 0
targetInvert            long 0[4]
invertFlag              long 0
invertPoints            long 0[4]
configNamePtr           long 0
fontFileName            long 0-0

machineState            byte Header#INIT_STATE
delimiter               byte 13, 10, ",", 9, 0
targetOledState         byte Header#DEMO_OLED
oledState               byte Header#DEMO_OLED
previousOledState        byte 255
maxDigits               byte Header#DEFAULT_MAX_DIGITS
debugLock               byte 255
sdLock                  byte 255
oledFileType            byte Header#NO_ACTIVE_OLED_TYPE
activeFont              byte Header#SIMPLYTROINICS_FONT 'FREE_DESIGN_FONT '_5_x_7_FONT '
previousBitmap          byte 255
fontWidth               byte 0-0
fontHeight              byte 0-0
fontFirstChar           byte 0-0
fontLastChar            byte 0-0
lineLimit               byte 0-0
columnLimit             byte 0-0
characterFlag           byte 0
rowOfBytes              byte 0[128]

PUB Start

  sdFlag := Header#INITIALIZING_SD

  Sd.fatEngineStart(Header#DOPIN, Header#ClkPIN, Header#DIPIN, Header#CSPIN, {
  } Header#WP_SD_PIN, Header#CD_SD_PIN, Header#RTC_PIN_1, Header#RTC_PIN_2, {
  } Header#RTC_PIN_3) 
  
  SetLocks
  SetFont(activeFont)
  
  Pst.str(string(11, 13, "SD Card Driver Started"))

  
  MountSd(Header#OLED_DATA_SD)

  longfill(@oledStack, Header#STACK_CHECK_LONG, Header#MONITOR_OLED_STACK_SIZE)
  
  result := cognew(OledMonitor, @oledStack)
  Pst.str(string(11, 13, "OledMonitor started on cog # "))
  Pst.Dec(result)   
  Pst.Char(".")
  'PressToContinue
  result := @oledStack
  
PRI SetLocks

  debugLock := locknew
  sdLock := locknew
  
PUB L

  repeat while lockset(debugLock)

PUB C

  lockclr(debugLock)
  
PUB LSd

  repeat while lockset(sdLock)

PUB CSd

  lockclr(sdLock)

PUB D 'ebugCog
'' display cog ID at the beginning of debug statements

  L
  Pst.Char(11)
  Pst.Char(13)
  Pst.Dec(cogid)
  Pst.Char(":")
  Pst.Char(32)
   
PUB ResetVerticalScroll

  activeScrollRow := 0
  
PUB SetFont(fontIndex)

  activeFont := fontIndex
  fontWidth := Header.GetFontWidth(fontIndex)
  fontHeight := Header.GetFontHeight(fontIndex)
  fontFirstChar := Header.GetFontFirst(fontIndex)
  fontLastChar := Header.GetFontLast(fontIndex)
  lineLimit := (Header#OLED_WIDTH / fontHeight) - 1      
  columnLimit := (Header#OLED_WIDTH / fontWidth) - 1
  fontFileName := Header.GetFontName(fontIndex)
  
PUB ScrollString(localStr, pstFlag)

  if activeScrollRow < Header#OLED_LINES - 1
    activeScrollRow++
  else
    ScrollBuffer(1)
    
  Write4x16String(localStr, strsize(localStr) <# 16, activeScrollRow, 0)
  if pstFlag
    Pst.ClearEnd
    Pst.Newline
    Pst.Str(localStr)
  UpdateDisplay
    
PUB WriteOledString(str, len, row, col, transparentFlag) | characterSize, bufferAddress, {
} eightByteBuffer[2], tempPtr, localDebugFlag


 { L
  Pst.str(string(11, 13, "WriteOledString(", 34))
  Pst.Str(str)
  Pst.str(string(34, ", "))
  Pst.Dec(len)
  Pst.str(string(", "))
  Pst.Dec(row)
  Pst.str(string(", "))
  Pst.Dec(col)
  Pst.str(string(", "))
  Pst.Dec(transparentFlag)
  Pst.str(string(")"))   
  C  }
  characterFlag := 0
  
  tempPtr := Spi.GetBuffer +  (row * 8) + col
  
  characterSize := 8 '((fontWidth + 7) / 8) * fontHeight ' *** think about this, which direction is up?

  'Pst.str(string(11, 13, "characterSize = "))
  'Pst.Dec(characterSize)
    
  {row *= fontHeight
  row <#= Header#OLED_HEIGHT - fontHeight
  col *= fontWidth
  col <#= Header#OLED_WIDTH - fontWidth   }
  bufferAddress := @eightByteBuffer 'Spi.GetPasmArea '* possible conflict with inverted buffer
  
  
  
  {if oledFileType <> Header#FONT_OLED_TYPE ' ** is this needed?
    if oledFileType == Header#GRAPHICS_OLED_TYPE
      LSd
      Sd[Header#OLED_DATA_SD].CloseFile
      CSd
    OpenFileToRead(Header#OLED_DATA_SD, fontFileName, -1)
    oledFileType := Header#FONT_OLED_TYPE     }
  'if activeFont <> Header#_5_x_7_FONT
    'SetFont(Header#_5_x_7_FONT)
    
  
  
  repeat len
    {Sd[Header#OLED_DATA_SD].FileSeek(((fontFirstChar #> byte[str] <# fontLastChar) - {
    } fontFirstChar) * characterSize)
    Sd[Header#OLED_DATA_SD].ReadData(bufferAddress, characterSize)
     }
    WriteChar(byte[str], row, col, transparentFlag)
    characterFlag := 1
    {
    if row == 0 and byte[str] => "0" and byte[str] =< "9"
      L
      Pst.str(string(11, 13, "Call FitBitmap("))
      Pst.Dec(Spi.GetBuffer)
      Pst.str(string(", "))
      Pst.Dec(Header#OLED_WIDTH)
      Pst.str(string(", "))
      Pst.Dec(Header#OLED_HEIGHT)
      Pst.str(string(", "))
      Pst.Dec(bufferAddress)
      Pst.str(string(", "))
      Pst.Dec(fontWidth)
      Pst.str(string(", "))
      Pst.Dec(fontHeight)
      Pst.str(string(", "))
      Pst.Dec(col)
      Pst.str(string(", "))
      Pst.Dec(row)
      Pst.str(string(", "))
      Pst.Dec(transparentFlag)
      Pst.str(string(")"))
      Pst.str(string(11, 13, "byte[str] = "))
      SafeTx(byte[str])  
      
      
      Pst.str(string(11, 13, "bufferAddress"))
      DisplayBytePixels(bufferAddress, 8)
      Pst.str(string(11, 13, "tempPtr"))
      DisplayBytePixels(tempPtr, 8)
      C
      localDebugFlag := 1
    else
      localDebugFlag := 0  
      'PressToContinueC
    FitBitmap(Spi.GetBuffer, Header#OLED_WIDTH, Header#OLED_HEIGHT, bufferAddress, {
    } fontWidth, fontHeight, col, row, transparentFlag)', localDebugFlag)
    }
    col++ '+= fontWidth
    tempPtr += characterSize '8
    {if row == 0 and byte[str] => "0" and byte[str] =< "9"
      L
      PressToContinueC   }
    str++  
    'Pst.str(string(11, 13, "col = "))
    'Pst.Dec(col)
  'UpdateDisplay
  'Sd[Header#OLED_DATA_SD].CloseFile
  
'if fontHeight == 8
 '   Write4x16String(str, len, row, col)
PUB WriteChar(character, row, col, transparentFlag) | eightByteBuffer[2], bufferAddress
'' For now all the characters have to be 8 pixels by 8 pixels.

  bufferAddress := @rowOfBytes 'eightByteBuffer
 { D
  Pst.str(string(11, 13, "oledFileType = "))
  Pst.Dec(oledFileType)
  C  }
  
  if oledFileType <> Header#FONT_OLED_TYPE
    if oledFileType == Header#GRAPHICS_OLED_TYPE
      'D
      'Pst.str(string(11, 13, "CloseFile"))
      LSd
      Sd[Header#OLED_DATA_SD].CloseFile
      CSd
      'C
    OpenFileToRead(Header#OLED_DATA_SD, fontFileName, -1)
    oledFileType := Header#FONT_OLED_TYPE

  'LSd
  'Sd[Header#OLED_DATA_SD].CloseFile
  'CSd
  'ifnot characterFlag 
  OpenFileToRead(Header#OLED_DATA_SD, fontFileName, -1)
  {D
  Pst.str(string(11, 13, "FileSeek("))
  Pst.Dec(((fontFirstChar #> character <# fontLastChar) - fontFirstChar) * 8)
  Pst.str(string(")"))
  C  }
  Sd[Header#OLED_DATA_SD].FileSeek(((fontFirstChar #> character <# fontLastChar) - {
    } fontFirstChar) * 8)
  'Sd[Header#OLED_DATA_SD].ReadData(bufferAddress, 8)
  'Sd[Header#OLED_DATA_SD].ReadData(@rowOfBytes, 8)
  ReadData(Header#OLED_DATA_SD, @rowOfBytes, 8)
  
  col <#= Header#MAX_OLED_CHAR_COL_INDEX
  row <#= Header#MAX_OLED_LINE_INDEX
 { D
  Pst.str(string(11, 13, "character = "))
  SafeTx(character)
  Pst.str(string(", col = "))
  Pst.Dec(col)
  Pst.str(string(", row ="))
  Pst.Dec(row)
  C   
  D
  PrintBitmap(@rowOfBytes, 8, 8)
  C   }
  'D
  FitBitmap(Spi.GetBuffer, Header#OLED_WIDTH, Header#OLED_HEIGHT, @rowOfBytes, {
  } fontWidth, fontHeight, col * 8, row * 8, transparentFlag, 0)', localDebugFlag)
  'C    
PUB DisplayBytePixels(localPtr, localSize)

  'L
  repeat localSize
    Pst.Str(string(11, 13, "byte["))
    Pst.Dec(localPtr)
    Pst.str(string("] = $"))
    Pst.Bin(byte[localPtr], 8)
    Pst.str(string(" or "))
    Pst.Dec(byte[localPtr])
    localPtr++

  'C
      
PUB Write4x16String(str, len, row, col)

  'Write4x16String(str, len, row, col)
  'if activeFont <> Header#_5_x_7_FONT
    'SetFont(Header#_5_x_7_FONT)
  WriteOledString(str, len, row, col, 0)

'PUB Write4x16String(str, len, row, col)

  'Spi.Write4x16String(str, len, row, col)
  
PUB ScrollBuffer(lines)
'' Positive values of "lines" will cause the buffer to scroll up, leaving room at the
'' bottom.

  lines := -7 #> lines <# 7
  if lines < 0
    bytemove(Spi.GetBuffer + (lines * Header#OLED_WIDTH), Spi.GetBuffer, {
    } Header#OLED_WIDTH * (Header#OLED_LINES - lines))
    bytefill(Spi.GetBuffer, 0, lines * Header#OLED_WIDTH)
  elseif lines > 0
    bytemove(Spi.GetBuffer, Spi.GetBuffer + (lines * Header#OLED_WIDTH), {
    } Header#OLED_WIDTH * (Header#OLED_LINES - lines))
    bytefill(Spi.GetBuffer + ((Header#OLED_LINES - lines) * Header#OLED_WIDTH), {
    } 0, lines * Header#OLED_WIDTH)
    
PUB SetOled(state, labelPtr, dataPtrPtr, dataQuantity)

  targetOledState := state 

  repeat until oledState == targetOledState

  longmove(@oledLabelPtr, @labelPtr, 3)
  'oledDataPtr, oledDataQuantity
  
{PRI OledMonitor : frozenState

  Spi.Start(Spi#SSD1306_SWITCHCAPVCC, Spi#TYPE_128X64, @shiftRegisterOutput, @debugSpi)
  
  repeat
    frozenState := oledState
    if frozenState <> previousOledState
      Spi.clearDisplay
    case frozenState 'oledState
      Header#DEMO_OLED:
        \OledDemo(frozenState)
      Header#MAIN_LOGO_OLED:
        \PropLogoLoop(frozenState)
      Header#AXES_READOUT_OLED:
        \ReadoutOled(frozenState)
      Header#BITMAP_OLED:
      Header#GRAPH_OLED:
    'Spi.clearDisplay
    previousOledState := frozenState
          }
PRI OledMonitor ': frozenState
  
  Spi.Start(Spi#SSD1306_SWITCHCAPVCC, Spi#TYPE_128X64)
  
  repeat
    oledState := targetOledState
      
    'frozenState := oledState ' we probably don't need frozenState now
    if oledState <> previousOledState
      Spi.clearDisplay
    case oledState
      Header#DEMO_OLED:
        \OledDemo(oledState)
        'LSd
        'Sd[Header#OLED_DATA_SD].CloseFile
        'CSd
      Header#MAIN_LOGO_OLED:
        \PropLogoLoop(oledState)
        'LSd
        'Sd[Header#OLED_DATA_SD].CloseFile
        'CSd
      Header#AXES_READOUT_OLED:
        \ReadoutOled(oledState)
        'LSd
        'Sd[Header#OLED_DATA_SD].CloseFile
        'CSd
      Header#BITMAP_OLED:
      Header#GRAPH_OLED:
      Header#PAUSE_MONITOR_OLED:
        ' do nothing
      Header#CLEAR_OLED:
        if previousOledState <> Header#CLEAR_OLED
          Spi.clearDisplay
        
    'Spi.clearDisplay
    previousOledState := oledState
      
PRI OledDemo(frozenState) | h, i, j, k, q, r, s, count

  
  ''For random number generation
  q := 12
  r := 200
  count := 1  'For display inversion control
  repeat

    ''**********************************
    ''Display the Adafruit Splash Screen
    ''**********************************
    PropLogo(frozenState)

    'result := WatchForChange(@targetOledState, Header#DEMO_OLED, 2_000)
    if WatchForChange(@targetOledState, frozenState, 2_000) 'result
      'Pst.str(string(11, 13, "result = "))
      'Pst.Dec(result)   
      'waitcnt(clkfreq * 3 + cnt)
      return
    'PressToContinue  
    {
    Spi.clearDisplay
                               '0123456789012345
    Spi.write4x16String(String("Based on code"), strsize(String("Based on code")), 2, 0)
    Spi.write4x16String(String("from . . ."), strsize(String("from . . .")), 4, 2)
    UpdateDisplay
    
    if WatchForChange(@targetOledState, frozenState, 2_000)
      return
    bytemove(Spi.getBuffer, Spi.getSplash, Spi#OLED_BUFFER_SIZE)
    UpdateDisplay

    if WatchForChange(@targetOledState, frozenState, 3_000)
      return
        }
    {Spi.write1x8String(String("Parallax"), strsize(String("Parallax")))
    Spi.write2x8String(String("Prop"), strsize(String("Prop")), 1)
    FitBitmap(Spi.getBuffer, 128, 64, @propBeanie, 32, 32, 96, 32, false)
    UpdateDisplay
    waitcnt(clkfreq*3+cnt)    }
    'repeat
    

    count++
    if count & $1
      Spi.invertDisplay(true)
    else  
      Spi.invertDisplay(false)
    UpdateDisplay

    if WatchForChange(@targetOledState, frozenState, 3_000)
      return
    
    ''******************************************
    ''Write random 5x7 characters to the display
    ''******************************************
    'AutoUpdate Off for more speed
    '''Spi.AutoUpdateOff
    Spi.clearDisplay
    repeat 1024
      if Spi.GetDisplayType == Spi#TYPE_128X32
        'Spi.Write5x7Char
        WriteChar(GetRandomChar, ||k? // 4, ||q? // 16, 0)
        
      else
        'Spi.Write5x7Char
        WriteChar(GetRandomChar, ||k? // 8, ||q? // 16, 0)
      UpdateDisplay
      
      if WatchForChange(@targetOledState, frozenState, 2)
        return
             
    
    ''******************************************************
    ''Display the contents of memory. Display the address as
    ''Hex, the value at that memory location as Hex and the
    ''value in memory as two lines of binary numbers (2*16)
    ''******************************************************
    '''Spi.AutoUpdateOff
    {Spi.clearDisplay
    repeat q from 0 to 512 step 16
      bytemove(@tstr, Num.ToStr(||word[q + 2], Num#BIN17), 20)
      Write4x16String(@tstr[1], 16, 0, 0)
      'Spi.write4x16String(@tstr[1], 16, 0, 0)
      bytemove(@tstr, Num.ToStr(||word[q + 0], Num#BIN17), 20)
      'Spi.w
      Write4x16String(@tstr[1], 16, 1, 0)
      bytemove(@tstr, Num.ToStr(||word[q + 6], Num#BIN17), 20)
      'Spi.w
      Write4x16String(@tstr[1], 16, 2, 0)
      bytemove(@tstr, Num.ToStr(||word[q + 4], Num#BIN17), 20)
      'Spi.w
      Write4x16String(@tstr[1], 16, 3, 0)
      if Spi.GetDisplayType == Spi#TYPE_128X64
        bytemove(@tstr, Num.ToStr(||word[q + 10], Num#BIN17), 20)
        'Spi.w
        Write4x16String(@tstr[1], 16, 4, 0)
        bytemove(@tstr, Num.ToStr(||word[q + 8], Num#BIN17), 20)
        'Spi.w
        Write4x16String(@tstr[1], 16, 5, 0)
        bytemove(@tstr, Num.ToStr(||word[q + 14], Num#BIN17), 20)
        'Spi.w
        Write4x16String(@tstr[1], 16, 6, 0)
        bytemove(@tstr, Num.ToStr(||word[q + 12], Num#BIN17), 20)
        'Spi.w
        Write4x16String(@tstr[1], 16, 7, 0)

      UpdateDisplay
      
      if WatchForChange(@targetOledState, frozenState, 100)
        return   }
               
    ''****************************************************
    ''Scrolling Parallax - 16x32 Font, 1 line 8 characters
    ''****************************************************
    ''''''Spi.AutoUpdateOn
    Spi.clearDisplay
    Spi.write1x8String(String("Parallax"), strsize(String("Parallax")))
    if Spi.GetDisplayType == Spi#TYPE_128X64
      Spi.write2x8String(String("  Inc.  "), strsize(String("  Inc.  ")), 1)

    if WatchForChange(@targetOledState, frozenState, 1_000)
      return
    
    Spi.startscrollleft(0, 31)

    if WatchForChange(@targetOledState, frozenState, 4_000)
      return

    Spi.startscrollright(0, 31)
    
    if WatchForChange(@targetOledState, frozenState, 4_000)
      return

    Spi.stopscroll
    
    if WatchForChange(@targetOledState, frozenState, 1_000)
      return

    ''******************************************
    ''Display a few screens full of random lines
    ''drawn end-to-end
    ''******************************************
    '''Spi.AutoUpdateOn
    repeat 5
      Spi.clearDisplay
    ' 'Start in the center of the screen
      j := 64
      k := 16
      repeat s from 1 to 100
        h := ||(q? // Spi.GetDisplayWidth)
        i := ||(r? // Spi.GetDisplayHeight)
        Spi.line(j, k, h, i, 1)
        j := h
        k := i
     
      if WatchForChange(@targetOledState, frozenState, 10)
        return

    
    ''******************************************
    ''Display a few screens full of random boxes
    ''******************************************
    '''Spi.AutoUpdateOn
    repeat 5
      Spi.ClearDisplay
    ' 'Start in the center of the screen
      j := 64
      k := 16
      repeat s from 1 to 50
        h := ||(q? // Spi.GetDisplayWidth)
        i := ||(r? // Spi.GetDisplayHeight)
        Spi.box(j, k, h, i, 1)
        j := h
        k := i
      
      if WatchForChange(@targetOledState, frozenState, 10)
        return

PRI PropLogoLoop(frozenState)
  
  repeat
    PropLogo(frozenState)
    if WatchForChange(@targetOledState, frozenState, 10_000)
      return
    
PRI PropLogo(frozenState)

  Spi.clearDisplay
  '''Spi.AutoUpdateOff
  'bytemove(Spi.getBuffer,Spi.getSplash,Spi#LCD_BUFFER_SIZE_BOTH_TYPES)
  Spi.write1x8String(String("Parallax"), strsize(String("Parallax")))
  Spi.write2x8String(String("Prop"), strsize(String("Prop")), 1)

  if true 'debugFlag
    D
    Pst.str(string(11, 13, "PropLogo Before UpdateDisplay"))
    'Pst.str(string(11, 13, "refreshCount = "))
    'Pst.Dec(Spi.GetRefreshCount)
    C
    
  UpdateDisplay
  SaveToBackground
  'waitcnt(clkfreq / 2 + cnt)
  if WatchForChange(@targetOledState, frozenState, 500)
    return

  if true 'debugFlag
    D
    Pst.str(string(11, 13, "PropLogo Before Bounce"))
    'Pst.str(string(11, 13, "refreshCount = "))
    'Pst.Dec(Spi.GetRefreshCount)
    C 'PressToContinue'C
  
  {BounceBitmap(frozenState, @propBeanie, 32, 32, {
  } 100, 40, -1, -1, 0, 0, 20, 0, 1)   } 
  {BounceBitmapNumber(frozenState, Header#BEANIE_SMALL_BITMAP, {
  } 100, 40, -1, -1, 0, 0, 0, 0, 1) }
  BounceBitmapNumber(frozenState, Header#LMR_LARGE_BITMAP, {
  } 100, 40, -1, -1, 0, 0, 0, 0, 1)

  if true 'debugFlag
    D
    Pst.str(string(11, 13, "PropLogo After Bounce"))
    'Pst.str(string(11, 13, "refreshCount = "))
    'Pst.Dec(Spi.GetRefreshCount)
    C
    
 { repeat result from 0 to 8
    FitBitmap(Spi.GetBuffer, 128, 64, @propBeanie, 32, 32, 100 - result, 40 - result, 0)
    UpdateDisplay
    RestoreBackground
    if WatchForChange(@targetOledState, frozenState, 200)
      return
  if WatchForChange(@targetOledState, frozenState, 2_000)
    return }

PUB BounceBitmapNumber(frozenState, bitmapIndex, startX, startY, directionX, directionY, {
} limitX, limitY, delay, moves, transparentFlag) | bufferAddress{, foregroundWidth, {
} foregroundHeight           }

  bufferAddress := Spi.GetPasmArea '* possible conflict with inverted buffer
  
  if oledFileType <> Header#GRAPHICS_OLED_TYPE '      
    if oledFileType == Header#FONT_OLED_TYPE
      LSd
      Sd[Header#OLED_DATA_SD].CloseFile
      CSd
    
    oledFileType := Header#GRAPHICS_OLED_TYPE

  'OpenFileToRead(Header#OLED_DATA_SD, Header.GetBitmapName(bitmapIndex), -1)

  'foregroundWidth := Header.GetBitmapWidth(bitmapIndex)
  'foregroundHeight := Header.GetBitmapHeight(bitmapIndex)
  
  'Sd[Header#OLED_DATA_SD].ReadData(bufferAddress, foregroundWidth * foregroundHeight / 8)  

  'PrintBitmap(bufferAddress, foregroundWidth, foregroundHeight)
  
  BounceBitmap(frozenState, bitmapIndex, startX, {
  } startY, directionX, directionY, limitX, limitY, delay, moves, transparentFlag)
 
PRI BounceBitmap(frozenState, bitmapIndex, {
} startX, startY, directionX, directionY, limitX, limitY, delay, moves, transparentFlag) {
} | position[2], direction[2]
'' The current buffer will be treated as the background bitmap.
'' Zero moves will cause this method to repeat a long time if not stopped.

  D
  Pst.str(string(11, 13, "Bounce"))
  C
  
  direction[0] := directionX
  direction[1] := directionY

  position[0] := startX
  position[1] := startY
  SaveToBackground
    
  repeat

  ' L
    {Pst.str(string(11, 13, "BounceBitmap Before FitBitmap"))
    Pst.str(string(11, 13, "refreshCount = "))
    Pst.Dec(Spi.GetRefreshCount)  }
    'PressToContinue'C
    'PrintBitmap(foreground, foregroundWidth, foregroundHeight)
    
    {FitBitmap(Spi.GetBuffer, 128, 64, foreground, foregroundWidth, foregroundHeight, {
    } position[0], position[1], transparentFlag, 1) }
    FitBitmapId(bitmapIndex, position[0], position[1], transparentFlag)
    'L
    {Pst.str(string(11, 13, "BounceBitmap After FitBitmap"))
    Pst.str(string(11, 13, "refreshCount = "))
    Pst.Dec(Spi.GetRefreshCount)}
    'PressToContinue'C

    UpdateDisplay

    'L
   { Pst.str(string(11, 13, "BounceBitmap After UpdateDisplay"))
    Pst.str(string(11, 13, "refreshCount = "))
    Pst.Dec(Spi.GetRefreshCount) }
    'PressToContinue'C
    
    RestoreBackground
    
    if position[0] == startX
      direction[0] := directionX
    elseif position[0] == limitX
      direction[0] := -directionX
    if position[1] == startY
      direction[1] := directionY
    elseif position[1] == limitY
      direction[1] := -directionY

    position[0] += direction[0]
    position[1] += direction[1]
    {Pst.str(string(11, 13, "("))
    'Pst.Char("(")
    Pst.Dec(position[0])  
    Pst.Char(",")
    Pst.Dec(position[1])  
    'Pst.Char(")")
    Pst.str(string(") Moving "))
    if direction[1] < 0
      Pst.str(string("up"))
    PressToContinue
      Pst.str(string("down"))  }
      
    if WatchForChange(@targetOledState, frozenState, delay)
      return
  while --moves    
  {
  PressToContinue
  Spi.clearDisplay
  
  repeat result from 96 to 0 step 32
    FitBitmap(Spi.GetBuffer, 128, 64, @propBeanie, 32, 32, result, 31, 0)
    UpdateDisplay
    waitcnt(clkfreq * 2 + cnt)
    
  PressToContinue
  
  Spi.clearDisplay
  FitBitmap(Spi.GetBuffer, 128, 64, @lmrVB, 32, 32, 8, 8, 0)
  UpdateDisplay

  PressToContinue
  
  Spi.clearDisplay
  FitBitmap(Spi.GetBuffer, 128, 64, @lmr64, 64, 64, 60, 0, 0)
  UpdateDisplay

  PressToContinue     }
   
PRI ReadoutOled(frozenState) | localIndex

  localIndex := 0
  maxDigits := Header#DEFAULT_MAX_DIGITS
  if oledDataQuantity > 2
    ReadoutOled8(frozenState)
  else
    repeat while localIndex < oledDataQuantity
      result := strsize(Header.FindString(oledLabelPtr, localIndex))
      if oledDataQuantity[localIndex] '<> $80_00_00_00
        result += maxDigits
      if result > 8
        ReadoutOled8(frozenState)
        return
      localIndex++
    result := ReadoutOled2(frozenState)
    if result == 1
      ReadoutOled8(frozenState)
        
PRI ReadoutOled2(frozenState) | labelPtr, dataPtrPtr, dataQuantity, len, row, bufferPtr, {
} localBuffer[5], remainingSpace, previousValue[8], maxIndex', temp

  repeat
    longmove(@labelPtr, @oledLabelPtr, 3) 
    maxIndex := dataQuantity - 1
    repeat row from 0 to maxIndex
      
      result := Format.Str(@localBuffer, labelPtr)
      if long[dataPtrPtr][row] '<> $80_00_00_00
        'temp := result
        result := Format.Dec(result, long[long[dataPtrPtr][row]])
        'temp := result - temp
        'maxDigits
      byte[result] := 0
      len := strsize(@localBuffer)
      remainingSpace := 8 - len
      if len > 8
        return 1
      if remainingSpace < 0
        byte[@localBuffer][16] := 0
      elseif remainingSpace > 0
        Format.Chstr(result, " ", remainingSpace)

      Spi.write2x8String(@localBuffer, 8, row)
      UpdateDisplay
      labelPtr += strsize(labelPtr) ' skip to next label
      labelPtr++ ' skip terminating zero
  while oledState == frozenState
  
PRI ReadoutOled8(frozenState) | labelPtr, dataPtrPtr, dataQuantity, len, row, bufferPtr, {
} localBuffer[5], remainingSpace, previousValue[8], maxIndex
  ' clear data?

  longfill(@previousValue, $80_00_00_00, 4)
  repeat
    longmove(@labelPtr, @oledLabelPtr, 3)
    maxIndex := dataQuantity - 1
    
    {if previousInvert
      RestoreBlock
      previousInvert := invertFlag
      bytemove(@previousPoints, @invertPoints, 4) }
    
    repeat row from 0 to maxIndex
      if true 'long[long[dataPtrPtr][row]] <> previousValue[row]
        previousValue[row] := long[long[dataPtrPtr][row]]
        result := Format.Str(@localBuffer, labelPtr)
        if long[dataPtrPtr][row] '<> $80_00_00_00 
          result := Format.Dec(result, long[long[dataPtrPtr][row]])
        byte[result] := 0
        len := strsize(@localBuffer)
        remainingSpace := 16 - len
        if remainingSpace < 0
          byte[@localBuffer][16] := 0
        elseif remainingSpace > 0
          Format.Chstr(result, " ", remainingSpace)
    
        'Spi.W
        Write4x16String(@localBuffer, 16, row, 0)
        
      labelPtr += strsize(labelPtr) ' skip to next label
      labelPtr++ ' skip terminating zero
    UpdateDisplay  
  while oledState == frozenState
   'oledLabelPtr, oledDataPtrPtr, oledDataQuantity
   
PUB WatchForChange(localPtr, expectedValue, timeToWait) | localTime

  timeToWait *= MS_001
  localTime := cnt
  repeat
    result := byte[localPtr] - expectedValue
  until cnt - localTime > timeToWait or result

  if result
    D
      Pst.str(string(11, 13, "CloseFile"))
    LSd
    Sd[Header#OLED_DATA_SD].CloseFile
    CSd
    C
    abort
              
PUB GetRandomChar | randomChar

  repeat
    result := ((||randomChar?) + 32) & $07F
  while result < 0 and result < 128  


{ FitBitmap does not work.}
PUB SaveToBackground

  bytemove(Spi.GetPasmArea, Spi.GetBuffer, Spi#OLED_BUFFER_SIZE)

PUB RestoreBackground

  bytemove(Spi.GetBuffer, Spi.GetPasmArea, Spi#OLED_BUFFER_SIZE)

VAR
  long previousActiveD
  
PUB PrintBitmap(mapPtr, mapWidth, mapHeight) | rowIndex
'' height needs to be in multiple of 8

  mapHeight /= 8
  rowIndex := mapHeight - 1
  
  repeat mapWidth
    repeat result from rowIndex to 0
      if result == rowIndex
        Pst.str(string(11, 13, "Map $"))
        Pst.Hex(mapPtr + (result * mapWidth), 8)
        Pst.str(string(" | $"))
      elseif result == 0
        Pst.Hex(mapPtr + (result * mapWidth), 8)
        Pst.str(string(" = %"))
      else
        Pst.Hex(mapPtr + (result * mapWidth), 8)
        Pst.str(string(" | $"))
        
    repeat result from rowIndex to 0
      Pst.Bin(byte[mapPtr + (result * mapWidth)], 8)
    mapPtr++  
      
PUB FitBitmapId(bitmapIndex, offsetX, offsetY, transparentFlag)

  'bufferAddress := Spi.GetPasmArea '* possible conflict with inverted buffer
  
  if oledFileType <> Header#GRAPHICS_OLED_TYPE '      
    if oledFileType == Header#FONT_OLED_TYPE
      LSd
      Sd[Header#OLED_DATA_SD].CloseFile
      CSd
    
    oledFileType := Header#GRAPHICS_OLED_TYPE
  {else
    LSd
    Sd[Header#OLED_DATA_SD].CloseFile
    CSd   }

  FitBitmap(Spi.GetBuffer, Header#OLED_WIDTH, Header#OLED_HEIGHT, {
  } Header.GetBitmapName(bitmapIndex), Header.GetBitmapWidth(bitmapIndex), {
  } Header.GetBitmapHeight(bitmapIndex), offsetX, offsetY, transparentFlag, 1)

PUB FitBitmap(destPtr, destWidth, destHeight, sourcePtr, sourceWidth, sourceHeight, {
} offsetX, offsetY, transparentFlag, fromSdFlag) | activeSourcePtr, activeDestPtr, arrayRowOffsetY, {
} byteOffset, {destRows,} sourceRows, outOfBounds[4], bitAdjust, tempSourcePtr
'' Vertical bytes
'' destWidth, destHeight, sourceWidth and sourceHeight in pixels
'' If reading bitmap from SD card, "sourcePtr" should contain the name of the file
'' holding the bitmap.

  if fromSdFlag 
    OpenFileToRead(Header#OLED_DATA_SD, sourcePtr, -1)
    sourcePtr := 0
    
  'pastSource := sourcePtr + (sourceWidth * sourceHeight / 8)
  
  {Pst.str(string(11, 13, "FitBitmap, destPtr = "))
  Pst.Dec(destPtr)
  Pst.str(string(11, 13, "sourcePtr = "))
  Pst.Dec(sourcePtr)}
{  Pst.str(string(11, 13, "FitBitmap, offsetX = "))
  'Pst.str(string(11, 13, "offsetX = "))
  Pst.Dec(offsetX)
  Pst.str(string(", old offsetY = "))
  Pst.Dec(offsetY)  }

  'byteOffset := 7 - (offsetY // 8)
  byteOffset := offsetY // 8
  bitAdjust := 7 - byteOffset
  offsetY -= byteOffset
  'offsetX <#= destWidth - sourceWidth

  {Pst.str(string(11, 13, "byteOffset = "))
  Pst.Dec(byteOffset)
  Pst.str(string(11, 13, "bitAdjust = "))
  Pst.Dec(bitAdjust)
  'Pst.str(string(11, 13, "new offsetX = "))
  'Pst.Dec(offsetX)
  Pst.str(string(11, 13, "new offsetY = "))
  Pst.Dec(offsetY)       }

  outOfBounds[0] := destPtr
  outOfBounds[1] := destPtr + (destWidth * destHeight / 8)
  
  activeSourcePtr := sourcePtr  '+ offsetX
  arrayRowOffsetY := offsetY / 8
  'activeSourcePtr += arrayRowOffsetY * sourceWidth '* 8
  activeDestPtr := destPtr + (destWidth * arrayRowOffsetY) + offsetX
  'destRows := destHeight / 8
  'destRows -= arrayRowOffsetY
  destHeight /= 8
  sourceRows := sourceHeight / 8
  'if byteOffset
    'activeDestPtr -= destWidth
    'sourceRows++ ' add one for partial row
    
 { Pst.str(string(11, 13, "sourceRows = "))
  Pst.Dec(sourceRows)
  Pst.str(string(11, 13, "activeDestPtr = "))
  Pst.Dec(activeDestPtr) 
  if previousActiveD
    Pst.str(string(11, 13, "previousActiveD = "))
    Pst.Dec(previousActiveD)   }
  previousActiveD := activeDestPtr
  {if fromSdFlag
    Sd[Header#OLED_DATA_SD].FileSeek(activeSourcePtr)
    Pst.str(string(11, 13, "FileSeek("))
    Pst.Dec(activeDestPtr)
    Pst.Char(")")    }
  repeat sourceRows 
    if activeDestPtr => outOfBounds[1]
      'Pst.str(string(11, 13, "activeDestPtr => outOfBounds[1]"))
      'PressToContinue 
      quit
    'elseif activeDestPtr < outOfBounds[0]
      'next

    if fromSdFlag
      {Sd[Header#OLED_DATA_SD].FileSeek(activeSourcePtr)
      Pst.str(string(11, 13, "FileSeek("))
      Pst.Dec(activeSourcePtr)
      Pst.Char(")")   }
       
      'Sd[Header#OLED_DATA_SD].ReadData(@rowOfBytes, sourceWidth)
      ReadData(Header#OLED_DATA_SD, @rowOfBytes, sourceWidth)
      tempSourcePtr := @rowOfBytes
    else
      tempSourcePtr := activeSourcePtr 
    
    if byteOffset 'true '
      if activeDestPtr < outOfBounds[0]
        outOfBounds[2] := outOfBounds[0]
      else
        outOfBounds[2] := activeDestPtr
      if activeDestPtr + destWidth > outOfBounds[1]
        outOfBounds[3] := outOfBounds[1]
      else
        outOfBounds[3] := activeDestPtr + destWidth
       
      MoveTopBits(activeDestPtr, destWidth, tempSourcePtr, sourceWidth, byteOffset, {
      } outOfBounds[2], outOfBounds[3], transparentFlag, 0)
      'UpdateDisplay
      'PressToContinue

      if activeDestPtr + destWidth < outOfBounds[0]
        outOfBounds[2] := outOfBounds[0]
      else
        outOfBounds[2] := activeDestPtr + destWidth
      if activeDestPtr + (2 * destWidth) > outOfBounds[1]
        outOfBounds[3] := outOfBounds[1]
      else
        outOfBounds[3] := activeDestPtr + (2 * destWidth)
          
      MoveBottomBits(activeDestPtr + destWidth, destWidth, tempSourcePtr, sourceWidth, byteOffset, {
      } outOfBounds[2], outOfBounds[3], transparentFlag, 0)
      'UpdateDisplay
      'PressToContinue
      
    else
      if activeDestPtr => outOfBounds[0] and activeDestPtr + sourceWidth < outOfBounds[1] ' full line in bounds
        MoveOrOrBytes(activeDestPtr, tempSourcePtr, sourceWidth, transparentFlag, 0)
      elseif activeDestPtr < outOfBounds[0] and activeDestPtr + sourceWidth => outOfBounds[0] ' end of line in bounds
        result := outOfBounds[0] - activeDestPtr ' how far out of bounds
        MoveOrOrBytes(outOfBounds[0], tempSourcePtr + result, sourceWidth - result, transparentFlag, fromSdFlag)
      elseif activeDestPtr < outOfBounds[1] ' beginning of line in bounds
        result := outOfBounds[1] - activeDestPtr
        MoveOrOrBytes(activeDestPtr, tempSourcePtr, result, transparentFlag, fromSdFlag)
        
        'Pst.str(string(11, 13, "outOfBounds[0] - activeDestPtr = "))
        'Pst.Dec(result)
    'UpdateDisplay
    'PressToContinue 
      {Pst.str(string(11, 13, "bytemove("))
      Pst.Dec(activeDestPtr)
      Pst.str(string(", "))
      Pst.Dec(activeSourcePtr)
      Pst.str(string(", "))
      Pst.Dec(sourceWidth)
      Pst.Char(")")     }
  
    activeDestPtr += destWidth '* 8
    activeSourcePtr += sourceWidth '* 8

  LSd
  Sd[Header#OLED_DATA_SD].CloseFile
  CSd
      
PUB MoveOrOrBytes(destPtr, sourcePtr, size, transparentFlag, fromSdFlag)

  if transparentFlag
    OrBytes(destPtr, sourcePtr, size, fromSdFlag)
  else
    if fromSdFlag
      'Sd[Header#OLED_DATA_SD].ReadData(destPtr, size)
      ReadData(Header#OLED_DATA_SD, destPtr, size) 
    else
      bytemove(destPtr, sourcePtr, size)
    
PUB MoveTopBits(activeDestPtr, destWidth, activeSourcePtr, sourceWidth, byteOffset, {
} outOfBoundsLow, outOfBoundsHigh, transparentFlag, fromSdFlag) | {
} fromSourceBitMask, notChangedBitMask, bitsAddedFromSource, debugPeriod
'' "byteOffset" is how many of the old bits should be kept.
'' Top bits from source. Top bits are the lowest bits in a byte.
'' The low bits from the source byte are moved to the high bits in the
'' destination byte. High bits are in the lower area of the displayed byte.
'' The terms "high" and "low" are opposite depending on if the bits
'' are in the display or in the byte.
'' High and low will refer to the bit position within a byte. Top and
'' bottom will refer to the position on the screen.


  debugPeriod := 0'1
  
  {Pst.str(string(11, 13, "MoveTopBits"))
  Pst.str(string(11, 13, "activeDestPtr = "))
  Pst.Dec(activeDestPtr)
  Pst.str(string(11, 13, "activeSourcePtr = "))
  Pst.Dec(activeSourcePtr)
  Pst.str(string(11, 13, "byteOffset = "))
  Pst.Dec(byteOffset)
  Pst.str(string(11, 13, " outOfBoundsLow = "))
  Pst.Dec(outOfBoundsLow) 
  Pst.str(string(11, 13, " outOfBoundsHigh = "))
  Pst.Dec(outOfBoundsHigh)   }
  
  'bitsAddedFromSource := 8 - byteOffset
  bitsAddedFromSource := byteOffset
  fromSourceBitMask := 0
  repeat bitsAddedFromSource 'byteOffset
    fromSourceBitMask >>= 1  ' replaced in the destination
    fromSourceBitMask |= %1000_0000
    'fromSourceBitMask <<= 1
    'fromSourceBitMask |= 1
  notChangedBitMask := !fromSourceBitMask  ' kept in the destination
  'Pst.str(string(11, 13, "fromSourceBitMask = "))
  'ReadableBin(fromSourceBitMask, 8)
 { Pst.str(string(11, 13, "notChangedBitMask = "))
  ReadableBin(notChangedBitMask, 8)   }

  
   
  repeat sourceWidth
    {ifnot result // debugPeriod
      Pst.str(string(11, 13, "original = "))
      ReadableBin(byte[activeDestPtr], 8)}
    if activeDestPtr => outOfBoundsLow and activeDestPtr < outOfBoundsHigh
   
      if transparentFlag == 0
        byte[activeDestPtr] &= notChangedBitMask
      {ifnot result // debugPeriod
        Pst.str(string(", trimmed = "))
        ReadableBin(byte[activeDestPtr], 8)}
      if fromSdFlag
        result := Sd[Header#OLED_DATA_SD].ReadByte
      else
        result := byte[activeSourcePtr]

      'result := byte[activeSourcePtr]
      result <<= bitsAddedFromSource  ' shift high to bottom
      'result <<= byteOffset '8 - bitsAddedFromSource  shift bit to top
    
      byte[activeDestPtr] |= result
    {else
      Pst.Char("^")
    if debugPeriod 'true 'not result // debugPeriod
      debugPeriod--
      Pst.str(string(", | = "))
      ReadableBin(byte[activeDestPtr], 8)

      Pst.str(string(11, 13, "byte["))
      Pst.Dec(activeSourcePtr)
      Pst.str(string("] = "))
      ReadableBin(byte[activeSourcePtr], 8)
       
      Pst.str(string(", adjusted = "))
      ReadableBin(result, 8)
      Pst.str(string(11, 13, "activeDestPtr = "))
      Pst.Dec(activeDestPtr) }
      
    activeDestPtr++
    activeSourcePtr++
    
PUB MoveBottomBits(activeDestPtr, destWidth, activeSourcePtr, sourceWidth, byteOffset, {
} outOfBoundsLow, outOfBoundsHigh, transparentFlag, fromSdFlag) | {
} fromSourceBitMask, keptBitsMask, bitsAddedFromSource, debugPeriod
'' Move bottom (high) bits from source to top (low) bits of destination.
  debugPeriod := 0' 1

  
  'Pst.str(string(11, 13, "MoveBottomBits"))

  'bitsAddedFromSource := byteOffset
  bitsAddedFromSource := 8 - byteOffset
  
  fromSourceBitMask := 0
  repeat bitsAddedFromSource 'byteOffset
    fromSourceBitMask <<= 1  ' replaced in the destination
    fromSourceBitMask |= 1
    'fromSourceBitMask >>= 1
    'fromSourceBitMask |= %1000_0000
  keptBitsMask := !fromSourceBitMask   ' keep low top bits
    
  repeat sourceWidth 
    {ifnot result // debugPeriod
      Pst.str(string(11, 13, "original = "))
      ReadableBin(byte[activeDestPtr], 8) }
    if activeDestPtr => outOfBoundsLow and activeDestPtr < outOfBoundsHigh
      if transparentFlag == 0      
        byte[activeDestPtr] &= keptBitsMask ' clear top bits (bit #0 is top bit)
    {ifnot result // debugPeriod
      Pst.str(string(", trimmed = "))
      ReadableBin(byte[activeDestPtr], 8) }
      if fromSdFlag
        result := Sd[Header#OLED_DATA_SD].ReadByte
      else
        result := byte[activeSourcePtr]
      
      result >>= bitsAddedFromSource  
     
      byte[activeDestPtr] |= result
    {else
      Pst.Char("v")
    if debugPeriod 'true 'not result // debugPeriod
      debugPeriod--
      Pst.str(string(", | = "))
      ReadableBin(byte[activeDestPtr], 8)

      Pst.str(string(11, 13, "byte["))
      Pst.Dec(activeSourcePtr)
      Pst.str(string("] = "))
      ReadableBin(byte[activeSourcePtr], 8)
       
      Pst.str(string(", adjusted = "))
      ReadableBin(result, 8)
      Pst.str(string(11, 13, "activeDestPtr = "))
      Pst.Dec(activeDestPtr)   }
      
    activeDestPtr++
    activeSourcePtr++

PUB OrBytes(destPtr, sourcePtr, size, fromSdFlag) 

  repeat size
    if fromSdFlag
      result := Sd[Header#OLED_DATA_SD].ReadByte
    else
      result := byte[sourcePtr++]
    byte[destPtr++] |= result
    
PUB UpdateDisplay '| frozenFlag
'' Keep track of which areas are buffer are inverted and uninvert before these areas
'' are changed.
'' When this program is called, there shouldn't be any inverted areas.
'' Inverted areas are inverted from calls within this method, displayed, then
'' uninverted.

  'frozenFlag := targetInvertFlag

  'previousInvert := invertFlag   
  'invertFlag <> targetInvertFlag 'frozenFlag
  longmove(@invertFlag, @targetInvertFlag, 5)
  'invertFlag := targetInvertFlag
  
  if invertFlag
    InvertBlock
    
  Spi.UpdateDisplay
  
  
  if invertFlag
    RestoreBlock
    '
    'bytemove(@previousPoints, @invertPoints, 4)
    
  'PressToContinue
  
PUB SetInvert(topLeftX, topLeftY, bottomRightX, bottomRightY)

  
  targetInvert[0] := topLeftX 
  targetInvert[1] := topLeftY
  targetInvert[2] := bottomRightX 
  targetInvert[3] := bottomRightY 
   
  targetInvertFlag := 1
  
  result := @invertPoints

PUB InvertOff

  targetInvertFlag := 0
  'UpdateDisplay
  result := @targetInvert
  
PRI RestoreBlock

  'D
  'Pst.str(string(11, 13, "RestoreBlock"))
  'PressToContinue
  InvertArea(invertPoints[0], invertPoints[1], invertPoints[2], invertPoints[3])
  'PressToContinueC
    
PRI InvertBlock

  {L
  Pst.PositionY(15)
  Pst.Char(11)
  Pst.Char(13)
  Pst.Dec(cogid)
  Pst.Char(":")
  Pst.Char(32)
  Pst.str(string(11, 13, "InvertBlock")) }
  'PressToContinue
  'InvertArea(targetInvert[0], targetInvert[1], targetInvert[2], targetInvert[3])
  InvertArea(invertPoints[0], invertPoints[1], invertPoints[2], invertPoints[3])
    
PRI InvertArea(topLeftX, topLeftY, bottomRightX, bottomRightY) | targetPtr, {topLeftRowY, 
} byteOffsetTop, byteOffsetBottom, blockWidth, blockHeight, blockRows, bufferAddress, {
 bufferHeight,} fullRows
'' Vertical bytes
'' destWidth, destHeight, sourceWidth and sourceHeight in pixels

  
  bufferAddress := Spi.GetBuffer

  topLeftX #>= Header#MIN_OLED_X
  topLeftY #>= Header#MIN_OLED_Y
  topLeftX <#= Header#MAX_OLED_X - Header#MIN_OLED_INVERTED_SIZE_X
  topLeftY <#= Header#MAX_OLED_Y - Header#MIN_OLED_INVERTED_SIZE_Y
  bottomRightX := topLeftX + Header#MIN_OLED_INVERTED_SIZE_X - 1 #> bottomRightX <# Header#MAX_OLED_X
  bottomRightY := topLeftY + Header#MIN_OLED_INVERTED_SIZE_Y - 1 #> bottomRightY <# Header#MAX_OLED_Y
  blockHeight := bottomRightY - topLeftY + 1
  blockWidth := bottomRightX - topLeftX + 1  
 { Pst.str(string(11, 13, "InvertArea, topLeftX = "))
  Pst.Dec(topLeftX)
  Pst.str(string(11, 13, "topLeftY = "))
  Pst.Dec(topLeftY)
  Pst.str(string(11, 13, "bottomRightX = "))
  Pst.Dec(bottomRightX)
  Pst.str(string(11, 13, "bottomRightY = "))
  Pst.Dec(bottomRightY)
  Pst.str(string(11, 13, "blockHeight = "))
  Pst.Dec(blockHeight)
  Pst.str(string(11, 13, "blockWidth = "))
  Pst.Dec(blockWidth) }
  
  {if restoreFlag
    Pst.str(string(11, 13, "Restore from inverted."))
  else
    Pst.str(string(11, 13, "Invert section."))
    longmove(@invertPoints, @topLeftX, 4)
    invertPoints[0] := topLeftX 
    invertPoints[1] := topLeftY
    invertPoints[2] := bottomRightX
    invertPoints[3] := bottomRightX  }
    
  'byteOffsetTop := 7 - (offsetY // 8)

  byteOffsetTop := topLeftY // 8  ' range 0 through 7
  targetPtr := bufferAddress + ((topLeftY / 8) * Header#OLED_WIDTH)
  'if byteOffsetTop
    'targetPtr += Header#OLED_WIDTH
  targetPtr += topLeftX
  
  byteOffsetBottom := blockHeight
  if byteOffsetTop
    byteOffsetBottom -= 8 - byteOffsetTop

  'Pst.str(string(11, 13, "height of combined full bytes and bottom partial byte = "))
  'Pst.Dec(byteOffsetBottom)
  fullRows := byteOffsetBottom / 8
  fullRows #>= 0  ' shouldn't be needed
  'byteOffsetBottom -= fullRows * 8
  byteOffsetBottom //= 8
  'byteOffsetBottom #>= 0
  'bitAdjust := 7 - byteOffsetTop
  'topLeftY -= byteOffsetTop
  'offsetX <#= destWidth - sourceWidth
  'topLeftY #>= 0
   
  {Pst.str(string(11, 13, "byteOffsetTop = "))
  Pst.Dec(byteOffsetTop)
  Pst.str(string(11, 13, "byteOffsetBottom = "))
  Pst.Dec(byteOffsetBottom)
  Pst.str(string(11, 13, "bufferAddress = "))
  Pst.Dec(bufferAddress)
  Pst.str(string(11, 13, "targetPtr = "))
  Pst.Dec(targetPtr)       
  Pst.str(string(11, 13, "fullRows = "))
  Pst.Dec(fullRows)       }
  'topLeftRowY := topLeftY / 8
  'activeSourcePtr += arrayRowOffsetY * sourceWidth '* 8
 
  
  'targetPtr := bufferAddress + (128 * topLeftRowY) + topLeftX
  'destRows := destHeight / 8
  'destRows -= arrayRowOffsetY
  'bufferHeight := 8
  'blockRows := (blockHeight + 7 - byteOffsetTop) / 8
  'if byteOffsetTop
    'activeDestPtr -= destWidth
    'sourceRows++ ' add one for partial row
    
 { Pst.str(string(11, 13, "sourceRows = "))
  Pst.Dec(sourceRows)
  Pst.str(string(11, 13, "activeDestPtr = "))
  Pst.Dec(activeDestPtr) 
  if previousActiveD
    Pst.str(string(11, 13, "previousActiveD = "))
    Pst.Dec(previousActiveD)   }
  'previousActiveD := activeDestPtr

  if byteOffsetTop
    
    InvertBottomOfTopBits(targetPtr, blockWidth, byteOffsetTop)
    'UpdateDisplay
    'PressToContinue
    targetPtr += Header#OLED_WIDTH 
  'PressToContinueC
  'L
     
  repeat fullRows 
    InvertFullBytes(targetPtr, blockWidth) 
    targetPtr += Header#OLED_WIDTH
  'PressToContinueC
  'L
    
  if byteOffsetBottom
    InvertTopOfBottomBits(targetPtr, blockWidth, byteOffsetBottom)
   'PressToContinueC
   'L
    
PRI InvertFullBytes(targetPtr, blockWidth)

  {Pst.str(string(11, 13, "InvertFullBytes("))
  Pst.Dec(targetPtr)
  Pst.str(string(", "))
  Pst.Dec(blockWidth)}
  'Spi.UpdateDisplay     
  'PressToContinue
  
  repeat blockWidth
    result := byte[targetPtr]
    byte[targetPtr] := !result
    targetPtr++

  'Pst.str(string(11, 13, "End of InvertFullBytes"))
  'Spi.UpdateDisplay     
  'PressToContinue
    
PRI InvertBottomOfTopBits(targetPtr, blockWidth, byteOffset) | {
} toInvertBitMask, notChangedBitMask, bitsToInvert, debugPeriod, tempTargetStatic, {
} tempTargetInvert
'' "byteOffset" is how many of the old bits should be kept.
'' Top bits from source. Top bits are the lowest bits in a byte.
'' The low bits from the source byte are moved to the high bits in the
'' destination byte. High bits are in the lower area of the displayed byte.
'' The terns "high" and "low" are opposite depending on if the bits
'' are in the display or in the byte.
'' High and low will refer to the bit position within a byte. Top and
'' bottom will refer to the position on the screen.


  debugPeriod := 0'1

  'Pst.str(string(11, 13, "InvertBottomOfTopBits, byteOffset = "))
  'Pst.Dec(byteOffset)       
  'PressToContinue
  
  {Pst.str(string(11, 13, "MoveTopBits"))
  Pst.str(string(11, 13, "targetPtr = "))
  Pst.Dec(targetPtr)
  Pst.str(string(11, 13, "activeSourcePtr = "))
  Pst.Dec(activeSourcePtr)
  Pst.str(string(11, 13, "byteOffset = "))
  Pst.Dec(byteOffset)
  Pst.str(string(11, 13, " outOfBoundsLow = "))
  Pst.Dec(outOfBoundsLow) 
  Pst.str(string(11, 13, " outOfBoundsHigh = "))
  Pst.Dec(outOfBoundsHigh)   }
  
  bitsToInvert := 8 - byteOffset
  'bitsToInvert := byteOffset
  toInvertBitMask := 0
  repeat bitsToInvert 'byteOffset
    toInvertBitMask >>= 1  ' replaced in the destination
    toInvertBitMask |= %1000_0000
    'toInvertBitMask <<= 1
    'toInvertBitMask |= 1
  notChangedBitMask := !toInvertBitMask  ' kept in the destination
  'Pst.str(string(11, 13, "toInvertBitMask = "))
  'ReadableBin(toInvertBitMask, 8)
 { Pst.str(string(11, 13, "notChangedBitMask = "))
  ReadableBin(notChangedBitMask, 8)   }
   
  repeat blockWidth
    'if targetPtr => outOfBoundsLow and targetPtr < outOfBoundsHigh
   
    tempTargetInvert := tempTargetStatic := byte[targetPtr]
    tempTargetStatic &= notChangedBitMask
    !tempTargetInvert
    tempTargetInvert &= toInvertBitMask
    {ifnot debugPeriod
      Pst.str(string(", trimmed = "))
      ReadableBin(byte[targetPtr], 8)}
      
    result := tempTargetInvert | tempTargetStatic
    {ifnot debugPeriod
      Pst.str(string(11, 13, "original byte = "))
      ReadableBin(byte[targetPtr], 8)
      Pst.str(string(11, 13, "tempTargetStatic = "))
      ReadableBin(tempTargetStatic, 8)
      Pst.str(string(11, 13, "tempTargetInvert = "))
      ReadableBin(tempTargetInvert, 8)
      Pst.str(string(11, 13, "result = "))
      ReadableBin(result, 8)
      debugPeriod++     }
    byte[targetPtr] := result
    {else
      Pst.Char("^")
    if debugPeriod 'true 'not result // debugPeriod
      debugPeriod--
      Pst.str(string(", | = "))
      ReadableBin(byte[targetPtr], 8)

      Pst.str(string(11, 13, "byte["))
      Pst.Dec(activeSourcePtr)
      Pst.str(string("] = "))
      ReadableBin(byte[activeSourcePtr], 8)
       
      Pst.str(string(", adjusted = "))
      ReadableBin(result, 8)
      Pst.str(string(11, 13, "targetPtr = "))
      Pst.Dec(targetPtr) }
      
    targetPtr++
  
    
PRI InvertTopOfBottomBits(targetPtr, blockWidth, byteOffset) | {
} toInvertBitMask, notChangedBitMask, bitsToInvert, debugPeriod, tempTargetStatic, {
} tempTargetInvert
'' "byteOffset" is how many of the old bits should be kept.
'' Top bits from source. Top bits are the lowest bits in a byte.
'' The low bits from the source byte are moved to the high bits in the
'' destination byte. High bits are in the lower area of the displayed byte.
'' The terns "high" and "low" are opposite depending on if the bits
'' are in the display or in the byte.
'' High and low will refer to the bit position within a byte. Top and
'' bottom will refer to the position on the screen.


  debugPeriod := 0'1
  
  'Pst.str(string(11, 13, "MoveTopBits"))
  {Pst.str(string(11, 13, "targetPtr = "))
  Pst.Dec(targetPtr)
  Pst.str(string(11, 13, "activeSourcePtr = "))
  Pst.Dec(activeSourcePtr)  }
  'Pst.str(string(11, 13, "byteOffset = "))
  'Pst.Dec(byteOffset)
  {Pst.str(string(11, 13, " outOfBoundsLow = "))
  Pst.Dec(outOfBoundsLow) 
  Pst.str(string(11, 13, " outOfBoundsHigh = "))
  Pst.Dec(outOfBoundsHigh)   }
  
  'bitsToInvert := 8 - byteOffset
  bitsToInvert := byteOffset
  toInvertBitMask := 0
  repeat bitsToInvert 'byteOffset
    'toInvertBitMask >>= 1  ' replaced in the destination
    'toInvertBitMask |= %1000_0000
    toInvertBitMask <<= 1
    toInvertBitMask |= 1
  notChangedBitMask := !toInvertBitMask  ' kept in the destination
  'Pst.str(string(11, 13, "toInvertBitMask = "))
  'ReadableBin(toInvertBitMask, 8)
 { Pst.str(string(11, 13, "notChangedBitMask = "))
  ReadableBin(notChangedBitMask, 8)   }
   
  repeat blockWidth
    {ifnot result // debugPeriod
      Pst.str(string(11, 13, "original = "))
      ReadableBin(byte[targetPtr], 8)}
    'if targetPtr => outOfBoundsLow and targetPtr < outOfBoundsHigh
   
    tempTargetInvert := tempTargetStatic := byte[targetPtr]
    tempTargetStatic &= notChangedBitMask
    !tempTargetInvert
    tempTargetInvert &= toInvertBitMask
    {ifnot result // debugPeriod
      Pst.str(string(", trimmed = "))
      ReadableBin(byte[targetPtr], 8)}
    result := tempTargetInvert | tempTargetStatic
    {ifnot debugPeriod
      Pst.str(string(11, 13, "original byte = "))
      ReadableBin(byte[targetPtr], 8)
      Pst.str(string(11, 13, "tempTargetStatic = "))
      ReadableBin(tempTargetStatic, 8)
      Pst.str(string(11, 13, "tempTargetInvert = "))
      ReadableBin(tempTargetInvert, 8)
      Pst.str(string(11, 13, "result = "))
      ReadableBin(result, 8)
      debugPeriod++   }
    byte[targetPtr] := result
    {else
      Pst.Char("^")
    if debugPeriod 'true 'not result // debugPeriod
      debugPeriod--
      Pst.str(string(", | = "))
      ReadableBin(byte[targetPtr], 8)

      Pst.str(string(11, 13, "byte["))
      Pst.Dec(activeSourcePtr)
      Pst.str(string("] = "))
      ReadableBin(byte[activeSourcePtr], 8)
       
      Pst.str(string(", adjusted = "))
      ReadableBin(result, 8)
      Pst.str(string(11, 13, "targetPtr = "))
      Pst.Dec(targetPtr) }
      
    targetPtr++
   
{PUB MoveBunchOfBits(destPtr, destWidth, sourcePtr, sourceWidth, offsetY)

  repeat destWidth  
    byte[destPtr] := MoveBits(sourcePtr, sourcePtr + sourceWidth, offsetY)
    destPtr++
    sourcePtr++
    
PUB MoveBits(sourcePtrTop, sourcePtrBottom, offsetY)

  {NewLine
  Pst.Str(string("MoveBits(")) 
  Pst.Dec(sourcePtrTop)  
  Pst.Str(string(", ")) 
  Pst.Dec(sourcePtrBottom)  
  Pst.Str(string(", ")) 
  Pst.Dec(offsetY)  
  Pst.Str(string(") ")) 
  NewLine
  Pst.Str(string("byte[sourcePtrTop] = ")) 
  ReadableBin(byte[sourcePtrTop], 8)
  NewLine
  Pst.Str(string("byte[sourcePtrBottom] = ")) 
  ReadableBin(byte[sourcePtrBottom], 8)
  }
  result := byte[sourcePtrTop] >> offsetY
  {NewLine
  Pst.Str(string("byte[sourcePtrTop] >> offsetY = ")) 
  ReadableBin(result, 8)      }
  result |= byte[sourcePtrBottom] << (8 - offsetY) 
 { NewLine
  Pst.Str(string("byte[sourcePtrBottom] << (8 - offsetY) = ")) 
  ReadableBin(byte[sourcePtrBottom] << (8 - offsetY), 8)
  NewLine
  Pst.Str(string("result = ")) 
  ReadableBin(result, 8)
   }

 }
PUB GetMultiplier

  result := globalMultiplier

PUB GetDecPoints

  result := globalDecPoints
{  
PUB GetDec(sdInstance) | inputCharacter, negativeFlag, startOfNumberFlag

  Pst.str(string(11, 13, "GetDec"))
  globalMultiplier := 0
  globalDecPoints := 0
  longfill(@negativeFlag, 0, 2)
  LSd
  repeat
    inputCharacter := Sd[sdInstance].readByte
    filePosition[sdInstance]++
    Pst.str(string(11, 13, "inputCharacter = "))
    SafeTx(inputCharacter)
    case inputCharacter
      "0".."9":
        startOfNumberFlag := 1
        result *= 10
        result += inputCharacter - "0"
        globalMultiplier *= 10
        if globalMultiplier
          globalDecPoints++
      ".":
        globalMultiplier := 1
      "-":
        negativeFlag := 1  
      " ":
        Pst.str(string(11, 13, "Ignore space character."))
      delimiter[0], delimiter[1], delimiter[2], delimiter[3], delimiter[4]:
        if startOfNumberFlag
          inputCharacter := delimiter[0]
        else
          inputCharacter := " "
      other:
        Pst.str(string(11, 13, "GetDec Error"))
        Pst.str(string(11, 13, "So far result = "))
        Pst.Dec(result)
        Pst.str(string(11, 13, "Unexpected byte = $"))
        Pst.Hex(inputCharacter, 2)
        PressToContinue
        'waitcnt(clkfreq * 2 + cnt)
    
  until inputCharacter == delimiter[0]
  CSd
  if negativeFlag
    -result
  ifnot globalMultiplier
    globalMultiplier := 1

  Pst.str(string(11, 13, "GetDec result = "))
  Pst.Dec(result)
        }
PUB OpenFileToRead(sdInstance, basePtr, fileToOpen)
'' sdLock should be cleared prior to calling this method.

  {if fileToOpen < 0
    Pst.str(string(11, 13, "Error in program.  Stopped at OpenFileToRead method."))
    result := Header#READ_FILE_ERROR_OTHER
    return }

  LSd  
  result := MountSd(sdInstance)
  if result == 1
    Pst.str(string(11, 13, "Error in program.  Problem mounting SD card."))
    waitcnt(clkfreq * 2 + cnt)
    result := Header#READ_FILE_ERROR_OTHER
    CSd
    return
  ''elseif result
    ''Pst.str(string(11, 13, "MountSd returned = "))
    ''Pst.str(result)
    'waitcnt(clkfreq * 2 + cnt)
    
  if fileToOpen => 0
    Decx(fileToOpen, 4, basePtr + Header#NUMBER_LOC_IN_FILE_NAME)
  ''Pst.str(string(11, 13, "Looking for file ", 34))
  ''Pst.str(basePtr)
  ''Pst.char(34)
  sdErrorString := \Sd[sdInstance].openFile(basePtr, "R")
  if strcomp(sdErrorString, basePtr)
    ''Pst.str(string(11, 13, "File ", 34))
    ''Pst.str(basePtr)
    ''Pst.str(string(34, " found."))
    result := Header#READ_FILE_SUCCESS
  else
    Pst.str(string(11, 13, "File ", 34))
    Pst.str(basePtr)
    Pst.str(string(34, " not found."))
    Pst.str(string(11, 13, "sdErrorString = "))
    Pst.dec(sdErrorString)
    Pst.str(string(11, 13, "sdErrorString ", 34))
    Pst.str(sdErrorString)
    Pst.char(34)
    UnmountSd(sdInstance)
   
    result := Header#FILE_NOT_FOUND
  CSd
  
PUB OpenOutputFileW(sdInstance, localPtr, fileIndex)

  LSd
  ifnot sdMountFlag[sdInstance] 
    Pst.str(string(11, 13, "Calling MountSd."))
    MountSd(sdInstance)
    
  if fileIndex => 0
    Decx(fileIndex, 4, localPtr + Header#NUMBER_LOC_IN_FILE_NAME)
  Pst.str(string(11, 13, "Attempting to create file ", 34))
  Pst.str(localPtr)
  Pst.char(34)

  repeat
    sdErrorString := \Sd[sdInstance].newFile(localPtr)
    sdErrorNumber :=  Sd[sdInstance].partitionError ' Returns zero if no error occurred.
       
    if(sdErrorNumber) ' Try to handle the "entry_already_exist" error.
      if(sdErrorNumber == Sd#Entry_Already_Exist)
        ' This section of code does not change "sdFlag" so this
        ' loop will repeat and try to open the next file number.
        
        'repeat until not lockset(debugLockID)
        if fileIndex => 0
          Pst.str(string(11, 13, "File ", 34))
          Pst.str(localPtr)
          Pst.str(string(34, " already exists."))
           
          Pst.str(string(11, 13, "Press ", QUOTE, "d", QUOTE, " to Delete older file and try again."))         
          Pst.str(string(11, 13, "Press ", QUOTE, "q", QUOTE, " to Quit and leave the older file on the SD card."))
          Pst.str(string(11, 13, "(Any other key will also cause the program to quit and to leave the older file on the SD card.)"))
          result := Pst.CharIn
          case result
            "d", "D":
              Sd[sdInstance].deleteEntry(localPtr)
              result := 0
        else
          Sd[sdInstance].deleteEntry(localPtr)
          result := 0
      else
 
        Pst.str(string(11, 13, "Create File Errror = "))
        Pst.dec(sdErrorNumber)
        
        waitcnt(clkfreq * 2 + cnt)
        result := -1
    else
      'sdFlag := NEW_LOG_CREATED_SD
      'repeat until not lockset(debugLockID) 
      Pst.str(string(11, 13, "Creating file ", 34))
      Pst.str(localPtr)
      Pst.str(string(34, "."))     
      'waitcnt(clkfreq / 4 + cnt)  
      Sd[sdInstance].openFile(localPtr, "W")
      result := 1
  until result 
  Csd
  
PUB OpenConfig(configPtr_)

  configPtr := configPtr_

  Pst.str(string(11, 13, "OpenConfig Method"))
  'PressToContinue
  'configNamePtr := Header.GetConfigName
  configNamePtr := Header.GetFileName(Header#CONFIG_FILE)
  
  result := OpenFileToRead(0, configNamePtr, -1)

  Pst.str(string(11, 13, "After OpenFileToRead Call"))
  'PressToContinue
  
{  if result == Header#READ_FILE_SUCCESS
    Sd[0].readData(configPtr, Header#CONFIG_SIZE)
  elseif result == Header#FILE_NOT_FOUND
    FillConfig
    machineState := Header#INIT_STATE
    return
  case configData[Header#MACHINE_STATE_OFFSET]
    Header#INIT_STATE:
    other:
                           }
{PRI FillConfig

  result := strsize(@programName) + @programName - Header#PROGRAM_VERSION_CHARACTERS
  bytemove(@configData + Header#VERSION_OFFSET_0, result, Header#PROGRAM_VERSION_CHARACTERS)
  }
PUB ReadData(instance, pointer, size)

  LSd
  result := Sd[instance].ReadData(pointer, size)
  CSd
   
PUB ReadByte(instance)

  result := Sd[instance].ReadByte
  
PUB WriteLong(endDat)

  result := Sd[0].WriteLong(endDat)
  
PUB WriteData(instance, pointer, size)

  result := Sd[instance].WriteData(pointer, size)

PUB CloseFile(instance)

  LSd
  Sd[instance].CloseFile
  CSd

PUB BootPartition(instance, pointer)

  if instance <> Header#OLED_DATA_SD
    UnmountSd(Header#OLED_DATA_SD)
  result := Sd[instance].BootPartition(pointer)

PUB ListEntries(instance, mode)

  result := Sd[instance].ListEntries(mode)
  
PUB Dec(value, localPtr)
'' Print a decimal number
  result := decl(value, 10, 0, localPtr)
  'byte[result] := _CarriageReturn
  
PUB Decf(value, width, localPtr)
'' Prints signed decimal value in space-padded, fixed-width field
  result := decl(value, width, 1, localPtr)

PUB Decx(value, digits, localPtr)
'' Prints zero-padded, signed-decimal string
'' -- if value is negative, field width is digits+1
  result := decl(value, digits, 2, localPtr)

PUB Decl(value, digits, flag, localPtr) | localI, localX
'' DWD Fixed with FDX 1.2 code

  digits := 1 #> digits <# 10
  
  localX := value == NEGX       'Check for max negative
  if value < 0
    value := ||(value + localX) 'If negative, make positive; adjust for max negative
    byte[localPtr++] := "-"
  localI := 1_000_000_000
  if flag & 3
    if digits < 10                                      ' less than 10 digits?
      repeat (10 - digits)                              '   yes, adjust divisor
        localI /= 10

  repeat digits
    if value => localI
      byte[localPtr++] := value / localI + "0" + localX * (localI == 1)
      value //= localI
      result~~
    elseif (localI == 1) OR result OR (flag & 2)
      byte[localPtr++] := "0"
    elseif flag & 1
      byte[localPtr++] := " "
    localI /= 10
  result := localPtr

PUB MountSd(sdInstance)
'' sdLock should be set (if used) prior to calling this method.
'' Returns 1 is no SD card is found.

  ''Pst.str(string(11, 13, "MountSd Method"))
  if sdMountFlag[sdInstance]
    result := string("SD Card Already Mounted")
    return  
  sdErrorNumber := Sd[sdInstance].mountPartition(0)
  ''Pst.str(string(11, 13, "After mount attempt.")) 
  if sdErrorNumber
    sdFlag := Header#NOT_FOUND_SD
    result := 1
    Pst.str(string(11, 13, "Error Mounting SD Card #"))
    Pst.dec(sdErrorNumber)
    
    if sdErrorNumber == -1
      Pst.str(string(11, 13, "The SD card was not properly unmounted after its last use."))
      Pst.str(string(11, 13, "Continuing with program."))
      sdFlag := Header#INITIALIZING_SD
      result := 0

  if result <> 1
    sdMountFlag[sdInstance] := 1

PUB UnmountSd(sdInstance)
'' sdLock should be set (if used) prior to calling this method.

  if sdMountFlag[sdInstance] == 0
    Pst.str(string(11, 13, "Partition not currently mounted."))
    return
  
  Pst.str(string(11, 13, "Unmounting Partition"))
  sdErrorNumber := Sd[sdInstance].unmountPartition
  Pst.str(string(11, 13, "sdErrorNumber = "))
  Pst.dec(sdErrorNumber)
  'outa[_GreenLedPin]~~
  'outa[_RedLedPin]~
  sdMountFlag[sdInstance] := 0
  
PUB DivideWithRound(numerator, denominator)

  if (numerator > 0 and denominator > 0) or {
    } (numerator < 0 and denominator < 0) 
    numerator += denominator / 2
  else
    numerator -= denominator / 2
    
  result := numerator / denominator

{PUB TtaMethodSigned(N, X, localD)   ' return X*N/D where all numbers and result are positive =<2^31

  result := 1
  if N < 0
    -N
    -result
  if X < 0
    -X
    -result
  if localD < 0
    -localD
    -result
    
  result *= TtaMethod(N, X, localD)

PUB TtaMethod(N, X, localD)   ' return X*N/D where all numbers and result are positive =<2^31
  return (N / localD * X) + (binNormal(N//localD, localD, 31) ** (X*2))

PUB BinNormal (y, x, b) : f                  ' calculate f = y/x * 2^b
' b is number of bits
' enter with y,x: {x > y, x < 2^31, y <= 2^31}
' exit with f: f/(2^b) =<  y/x =< (f+1) / (2^b)
' that is, f / 2^b is the closest appoximation to the original fraction for that b.
  repeat b
    y <<= 1
    f <<= 1
    if y => x    '
      y -= x
      f++
  if y << 1 => x    ' Round off. In some cases better without.
      f++

PUB FindString(firstStr, stringIndex)      

  result := Header.FindString(firstStr, stringIndex)
 }   
PUB PauseForInput

  Pst.Str(string(11, 13, "Press any key to continue."))
  result := Pst.CharIn

PUB SafeTx(localCharacter)
'' Debug lock should be set prior to calling this method.

  if (localCharacter > 32 and localCharacter < 127)
    Pst.Char(localCharacter)    
  else
    Pst.Char(60)
    Pst.Char(36) 
    Pst.Hex(localCharacter, 2)
    Pst.Char(62)

PUB ReadableBin(localValue, size) | bufferPtr, localBuffer[12]    
'' This method display binary numbers
'' in easier to read groups of four
'' format.

  bufferPtr := Format.Ch(@localBuffer, "%")
  
  result := size // 4
   
  if result
    size -= result
    bufferPtr := Format.Bin(bufferPtr, localValue >> size, result)
    if size
      bufferPtr := Format.Ch(bufferPtr, "_")
  size -= 4
 
  repeat while size => 0
    bufferPtr := Format.Bin(bufferPtr, localValue >> size, 4)
    if size
      bufferPtr := Format.Ch(bufferPtr, "_")  
    size -= 4
    
  byte[bufferPtr] := 0  
  Pst.Str(@localBuffer)
  
PUB PressToPause

  result := Pst.RxCount
  if result
    Pst.str(string(11, 13, "Paused."))
    Pst.RxFlush
    PressToContinue
    
PUB PressToContinue
  
  Pst.str(string(11, 13, "Press to continue."))
  repeat
    result := Pst.RxCount
  until result
  Pst.RxFlush

PUB PressToContinueC
  
  Pst.str(string(11, 13, "Press to continue."))
  C
  repeat
    L
    result := Pst.RxCount
    C
  until result

  L
  Pst.RxFlush
  C
  
PUB GetOledBuffer

  result := Spi.GetBuffer
