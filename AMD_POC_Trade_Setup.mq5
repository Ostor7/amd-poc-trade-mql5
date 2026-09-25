//+------------------------------------------------------------------+
//|                                        AMD_POC_Trade_Setup.mq5   |
//| AMD POC Trade Setup Indicator for MetaTrader 5                   |
//| Converted from Pine Script v6                                    |
//| Subject to Mozilla Public License 2.0                            |
//+------------------------------------------------------------------+
#property copyright "Converted from Pine Script v6"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

// Input parameters
input int      AccLen = 40;                  // Accumulation Length (Bars)
input double   AccWidth = 0.1;               // Accumulation Range Max %
input bool     NormalizeAccWidth = true;     // Normalize Range Threshold
input string   ReferenceTf = "1";            // Normalization Reference Timeframe (in minutes)
input int      ManLook = 20;                 // Max Search Window
input double   MinPocBreakAtr = 0.15;        // Minimum POC Break (ATR)
input double   MinBreakBodyAtr = 0.20;       // Minimum Break Candle Body (ATR)
input double   BreakCloseStrength = 0.65;    // Break Candle Close Strength

input int      ProfileRows = 24;             // Volume Profile Rows
input int      ProfileWidth = 18;            // Maximum Profile Width
input bool     ShowProfile = true;           // Show Accumulation Volume Profile

input bool     UseSydney = false;            // Sydney Session (17:00-02:00 EST)
input bool     UseTokyo = false;             // Tokyo Session (19:00-04:00 EST)
input bool     UseLondon = false;            // London Session (03:00-12:00 EST)
input bool     UseNY = true;                 // New York Session (08:00-17:00 EST)
input bool     ShowSess = true;              // Highlight Active Session Time

input color    AccColor = C'192,192,192';    // Accumulation color (gray)
input color    ManColor = C'242,54,69';      // Manipulation Bearish (red)
input color    ManColorB = C'8,153,129';     // Manipulation Bullish (green)
input color    ProfileColor = C'91,156,246'; // Volume Profile (blue)
input color    POCColor = C'242,54,69';      // Point of Control (red)
input color    TPColor = C'8,153,129';       // Take Profit (green)
input color    SLColor = C'242,54,69';       // Stop Loss (red)

// State variables
double accHigh = 0.0;
double accLow = 0.0;
int accStartBar = -1;
int accEndBar = -1;
bool manipulationHigh = false;
bool manipulationLow = false;
double manipulationExtremum = 0.0;

bool profileReady = false;
double profilePoc = 0.0;
double profileVolumes[];
int atrHandle = INVALID_HANDLE;

int tpBoxObjId = -1;
int slBoxObjId = -1;
double entryLevel = 0.0;
double tpLevel = 0.0;
double slLevel = 0.0;
bool isTradeActive = false;
bool isBullishTrade = false;

int barCounter = 0;

// Price data buffers
double closeBuffer[];
double openBuffer[];
double highBuffer[];
double lowBuffer[];
double volumeBuffer[];
double atrBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    ArrayResize(profileVolumes, ProfileRows, 0);
    ArrayResize(closeBuffer, AccLen + ManLook + 10, 0);
    ArrayResize(openBuffer, AccLen + ManLook + 10, 0);
    ArrayResize(highBuffer, AccLen + ManLook + 10, 0);
    ArrayResize(lowBuffer, AccLen + ManLook + 10, 0);
    ArrayResize(volumeBuffer, AccLen + ManLook + 10, 0);
    ArrayResize(atrBuffer, AccLen + ManLook + 10, 0);
    
    // Create ATR indicator handle
    atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Error creating ATR handle");
        return INIT_FAILED;
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up drawing objects on exit
    ObjectsDeleteAll(0, 0, OBJ_RECTANGLE);
    ObjectsDeleteAll(0, 0, OBJ_TREND);
    
    // Release indicator handle
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Process only on new bar
    static int lastBar = -1;
    if(lastBar == Bars(Symbol(), PERIOD_CURRENT))
        return;
    
    lastBar = Bars(Symbol(), PERIOD_CURRENT);
    int currentBar = lastBar - 1;

    // Check if we're in an active session
    bool inSession = IsInAnySession();
    
    if(!inSession)
        return;

    // Copy price data
    if(CopyClose(Symbol(), PERIOD_CURRENT, 0, AccLen + ManLook + 5, closeBuffer) <= 0)
        return;
    if(CopyOpen(Symbol(), PERIOD_CURRENT, 0, AccLen + ManLook + 5, openBuffer) <= 0)
        return;
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, AccLen + ManLook + 5, highBuffer) <= 0)
        return;
    if(CopyLow(Symbol(), PERIOD_CURRENT, 0, AccLen + ManLook + 5, lowBuffer) <= 0)
        return;
    if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, AccLen + ManLook + 5, volumeBuffer) <= 0)
        return;
    if(CopyBuffer(atrHandle, 0, 0, AccLen + ManLook + 5, atrBuffer) <= 0)
        return;

    // Get current bar data (index 0 is current bar)
    double close = closeBuffer[0];
    double open = openBuffer[0];
    double high = highBuffer[0];
    double low = lowBuffer[0];
    double volume = volumeBuffer[0];
    double atr = atrBuffer[0];

    // Calculate timeframe scale
    int chartSeconds = PeriodSeconds(PERIOD_CURRENT);
    int referenceSeconds = StringToTimeframe(ReferenceTf) * 60;
    if(referenceSeconds == 0) referenceSeconds = 60;
    
    double timeframeScale = MathSqrt((double)chartSeconds / referenceSeconds);
    double effectiveAccWidth = NormalizeAccWidth ? AccWidth * timeframeScale : AccWidth;

    // --- Accumulation Detection ---
    double highs = GetHighest(highBuffer, AccLen);
    double lows = GetLowest(lowBuffer, AccLen);
    double rangePct = lows != 0.0 ? (highs - lows) / lows * 100.0 : 0.0;
    
    bool isAccumulating = (rangePct <= effectiveAccWidth);

    if(isAccumulating && !isTradeActive)
    {
        accHigh = highs;
        accLow = lows;
        accStartBar = currentBar - AccLen + 1;
        accEndBar = currentBar;
        manipulationHigh = false;
        manipulationLow = false;
        manipulationExtremum = 0.0;
        profileReady = false;
        profilePoc = 0.0;
    }

    // --- Trade Lifecycle ---
    if(isTradeActive)
    {
        // Check exit conditions
        if(isBullishTrade)
        {
            if(low <= slLevel || high >= tpLevel)
                isTradeActive = false;
        }
        else
        {
            if(high >= slLevel || low <= tpLevel)
                isTradeActive = false;
        }
    }

    // --- Manipulation and POC Break Detection ---
    if(!isAccumulating && accHigh != 0.0 && accLow != 0.0 && 
       currentBar <= accEndBar + ManLook && inSession)
    {
        bool startsBearishManipulation = !manipulationHigh && !manipulationLow && high > accHigh;
        bool startsBullishManipulation = !manipulationHigh && !manipulationLow && low < accLow;

        if(startsBearishManipulation)
        {
            manipulationHigh = true;
            manipulationExtremum = high;
        }
        else if(startsBullishManipulation)
        {
            manipulationLow = true;
            manipulationExtremum = low;
        }

        // Build volume profile on first manipulation
        if((startsBearishManipulation || startsBullishManipulation) && !profileReady)
        {
            BuildVolumeProfile(accStartBar, accEndBar, lowBuffer, highBuffer, volumeBuffer);
            profileReady = true;

            // Draw accumulation range box
            DrawAccumulationBox(accStartBar, accEndBar, accHigh, accLow);

            // Draw POC line
            DrawPOCLine(accStartBar, accEndBar, profilePoc);
        }

        // Update manipulation extremum
        if(manipulationHigh)
            manipulationExtremum = MathMax(manipulationExtremum, high);
        if(manipulationLow)
            manipulationExtremum = MathMin(manipulationExtremum, low);

        // Calculate break confirmation metrics
        double breakBody = MathAbs(close - open);
        double breakRange = high - low;
        double bearCloseStrengthValue = breakRange > 0.0 ? (high - close) / breakRange : 0.0;
        double bullCloseStrengthValue = breakRange > 0.0 ? (close - low) / breakRange : 0.0;

        // --- Bearish Setup ---
        bool bearPocBreak = manipulationHigh && profileReady &&
                            close < profilePoc - atr * MinPocBreakAtr &&
                            close < open &&
                            breakBody >= atr * MinBreakBodyAtr &&
                            bearCloseStrengthValue >= BreakCloseStrength;

        if(bearPocBreak && !isTradeActive)
        {
            // Draw manipulation box
            DrawManipulationBox(accEndBar, manipulationExtremum, currentBar, accHigh, ManColor);

            entryLevel = profilePoc;
            slLevel = accHigh;
            tpLevel = accLow;
            isTradeActive = true;
            isBullishTrade = false;

            // Draw TP and SL boxes
            DrawTPBox(currentBar, entryLevel, tpLevel);
            DrawSLBox(currentBar, entryLevel, slLevel);

            // Alert
            Alert("Bearish AMD TP/SL Trade Setup");
            Print("Bearish Setup: Entry=", entryLevel, " TP=", tpLevel, " SL=", slLevel);

            accHigh = 0.0;
            accLow = 0.0;
            profileReady = false;
            manipulationHigh = false;
        }

        // --- Bullish Setup ---
        bool bullPocBreak = manipulationLow && profileReady &&
                            close > profilePoc + atr * MinPocBreakAtr &&
                            close > open &&
                            breakBody >= atr * MinBreakBodyAtr &&
                            bullCloseStrengthValue >= BreakCloseStrength;

        if(bullPocBreak && !isTradeActive)
        {
            // Draw manipulation box
            DrawManipulationBox(accEndBar, accLow, currentBar, manipulationExtremum, ManColorB);

            entryLevel = profilePoc;
            slLevel = accLow;
            tpLevel = accHigh;
            isTradeActive = true;
            isBullishTrade = true;

            // Draw TP and SL boxes
            DrawTPBox(currentBar, entryLevel, tpLevel);
            DrawSLBox(currentBar, entryLevel, slLevel);

            // Alert
            Alert("Bullish AMD TP/SL Trade Setup");
            Print("Bullish Setup: Entry=", entryLevel, " TP=", tpLevel, " SL=", slLevel);

            accHigh = 0.0;
            accLow = 0.0;
            profileReady = false;
            manipulationLow = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if in active trading session                               |
//+------------------------------------------------------------------+
bool IsInAnySession()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    int hour = timeStruct.hour;
    int minute = timeStruct.min;
    int totalMinutes = hour * 60 + minute;

    // Sydney: 17:00 - 02:00 (1020 - 120, wraps)
    if(UseSydney)
    {
        if(totalMinutes >= 17*60 || totalMinutes < 2*60)
            return true;
    }

    // Tokyo: 19:00 - 04:00 (1140 - 240, wraps)
    if(UseTokyo)
    {
        if(totalMinutes >= 19*60 || totalMinutes < 4*60)
            return true;
    }

    // London: 03:00 - 12:00 (180 - 720, no wrap)
    if(UseLondon)
    {
        if(totalMinutes >= 3*60 && totalMinutes < 12*60)
            return true;
    }

    // New York: 08:00 - 17:00 (480 - 1020, no wrap)
    if(UseNY)
    {
        if(totalMinutes >= 8*60 && totalMinutes < 17*60)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Get highest value from buffer                                    |
//+------------------------------------------------------------------+
double GetHighest(double &buffer[], int count)
{
    double highest = buffer[0];
    for(int i = 1; i < count && i < ArraySize(buffer); i++)
    {
        if(buffer[i] > highest)
            highest = buffer[i];
    }
    return highest;
}

//+------------------------------------------------------------------+
//| Get lowest value from buffer                                     |
//+------------------------------------------------------------------+
double GetLowest(double &buffer[], int count)
{
    double lowest = buffer[0];
    for(int i = 1; i < count && i < ArraySize(buffer); i++)
    {
        if(buffer[i] < lowest)
            lowest = buffer[i];
    }
    return lowest;
}

//+------------------------------------------------------------------+
//| Build volume profile from accumulation bars                       |
//+------------------------------------------------------------------+
void BuildVolumeProfile(int startBar, int endBar, double &lowBuf[], double &highBuf[], double &volBuf[])
{
    ArrayFill(profileVolumes, 0, ProfileRows, 0.0);

    double profileStep = (accHigh - accLow) / ProfileRows;
    if(profileStep <= 0.0)
        return;

    double maxProfileVolume = 0.0;
    int accumulationBars = MathMax(1, endBar - startBar + 1);

    // Calculate volume for each row
    for(int row = 0; row < ProfileRows; row++)
    {
        double rowLow = accLow + profileStep * row;
        double rowHigh = rowLow + profileStep;
        double rowVolume = 0.0;

        // Sum volume from bars in accumulation range
        for(int offset = 0; offset < accumulationBars && offset < 500; offset++)
        {
            int barIdx = startBar + offset;
            if(barIdx < 0 || barIdx >= ArraySize(lowBuf)) continue;

            double barLow = lowBuf[barIdx];
            double barHigh = highBuf[barIdx];
            double barRange = barHigh - barLow;
            double overlap = MathMax(0.0, MathMin(rowHigh, barHigh) - MathMax(rowLow, barLow));
            double volumeShare = barRange > 0.0 ? volBuf[barIdx] * overlap / barRange : 0.0;

            rowVolume += volumeShare;
        }

        profileVolumes[row] = rowVolume;
        maxProfileVolume = MathMax(maxProfileVolume, rowVolume);
    }

    // Find POC (highest volume row)
    int pocRow = 0;
    double pocVolume = profileVolumes[0];
    for(int row = 1; row < ProfileRows; row++)
    {
        if(profileVolumes[row] > pocVolume)
        {
            pocVolume = profileVolumes[row];
            pocRow = row;
        }
    }

    profilePoc = accLow + profileStep * (pocRow + 0.5);
}

//+------------------------------------------------------------------+
//| Draw accumulation range box                                       |
//+------------------------------------------------------------------+
void DrawAccumulationBox(int startBar, int endBar, double high, double low)
{
    string objName = "Acc_" + IntegerToString(startBar) + "_" + IntegerToString(endBar);
    
    ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                 iTime(Symbol(), PERIOD_CURRENT, startBar), high,
                 iTime(Symbol(), PERIOD_CURRENT, endBar), low);
    
    ObjectSetInteger(0, objName, OBJPROP_FILL, true);
    ObjectSetInteger(0, objName, OBJPROP_BACK, true);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, AccColor);
}

//+------------------------------------------------------------------+
//| Draw manipulation range box                                       |
//+------------------------------------------------------------------+
void DrawManipulationBox(int startBar, double high, int endBar, double low, color clr)
{
    string objName = "Man_" + IntegerToString(startBar) + "_" + IntegerToString(endBar);
    
    ObjectCreate(0, objName, OBJ_RECTANGLE, 0,
                 iTime(Symbol(), PERIOD_CURRENT, startBar), high,
                 iTime(Symbol(), PERIOD_CURRENT, endBar), low);
    
    ObjectSetInteger(0, objName, OBJPROP_FILL, true);
    ObjectSetInteger(0, objName, OBJPROP_BACK, true);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Draw POC line                                                     |
//+------------------------------------------------------------------+
void DrawPOCLine(int startBar, int endBar, double poc)
{
    string objName = "POC_" + IntegerToString(startBar);
    
    ObjectCreate(0, objName, OBJ_TREND, 0,
                 iTime(Symbol(), PERIOD_CURRENT, startBar), poc,
                 iTime(Symbol(), PERIOD_CURRENT, endBar), poc);
    
    ObjectSetInteger(0, objName, OBJPROP_COLOR, POCColor);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, objName, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Draw Take Profit box                                              |
//+------------------------------------------------------------------+
void DrawTPBox(int currentBar, double entry, double tp)
{
    string objName = "TP_" + IntegerToString(currentBar) + "_" + IntegerToString(TimeCurrent());
    
    double boxHigh = MathMax(entry, tp);
    double boxLow = MathMin(entry, tp);
    
    ObjectCreate(0, objName, OBJ_RECTANGLE, 0,
                 TimeCurrent(), boxHigh,
                 TimeCurrent(), boxLow);
    
    ObjectSetInteger(0, objName, OBJPROP_FILL, true);
    ObjectSetInteger(0, objName, OBJPROP_BACK, false);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, TPColor);
}

//+------------------------------------------------------------------+
//| Draw Stop Loss box                                                |
//+------------------------------------------------------------------+
void DrawSLBox(int currentBar, double entry, double sl)
{
    string objName = "SL_" + IntegerToString(currentBar) + "_" + IntegerToString(TimeCurrent());
    
    double boxHigh = MathMax(entry, sl);
    double boxLow = MathMin(entry, sl);
    
    ObjectCreate(0, objName, OBJ_RECTANGLE, 0,
                 TimeCurrent(), boxHigh,
                 TimeCurrent(), boxLow);
    
    ObjectSetInteger(0, objName, OBJPROP_FILL, true);
    ObjectSetInteger(0, objName, OBJPROP_BACK, false);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, SLColor);
}

//+------------------------------------------------------------------+
//| Convert timeframe string to ENUM_TIMEFRAMES                       |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTimeframe(string tf)
{
    if(tf == "1") return PERIOD_M1;
    if(tf == "5") return PERIOD_M5;
    if(tf == "15") return PERIOD_M15;
    if(tf == "30") return PERIOD_M30;
    if(tf == "60") return PERIOD_H1;
    if(tf == "240") return PERIOD_H4;
    if(tf == "1440") return PERIOD_D1;
    if(tf == "10080") return PERIOD_W1;
    if(tf == "43200") return PERIOD_MN1;
    return PERIOD_H1; // Default
}

//+------------------------------------------------------------------+
//| End of Expert Advisor                                             |
//+------------------------------------------------------------------+
