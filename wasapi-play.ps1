# WASAPI shared-mode WAV player with resampling (modern audio stack, Bluetooth-friendly)
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

$cs = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    int RegisterEndpointNotificationCallback(IntPtr client);
    int UnregisterEndpointNotificationCallback(IntPtr client);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection {
    int GetCount(out int count);
    int Item(int index, out IMMDevice device);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
    int OpenPropertyStore(int stgmAccess, out IntPtr properties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    int GetState(out int state);
}

[Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioClient {
    int Initialize(int shareMode, int streamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, IntPtr audioSessionGuid);
    int GetBufferSize(out int numBufferFrames);
    int GetStreamLatency(out long hnsLatency);
    int GetCurrentPadding(out int numPaddingFrames);
    int IsFormatSupported(int shareMode, IntPtr pFormat, out IntPtr closestMatch);
    int GetMixFormat(out IntPtr deviceFormat);
    int GetDevicePeriod(out long hnsDefaultDevicePeriod, out long hnsMinimumDevicePeriod);
    int Start();
    int Stop();
    int Reset();
    int SetEventHandle(IntPtr eventHandle);
    int GetService(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
}

[Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioRenderClient {
    int GetBuffer(int numFramesRequested, out IntPtr dataBufferPointer);
    int ReleaseBuffer(int numFramesWritten, int bufferFlags);
}

[StructLayout(LayoutKind.Sequential)]
public struct WAVEFORMATEX {
    public ushort wFormatTag;
    public ushort nChannels;
    public uint nSamplesPerSec;
    public uint nAvgBytesPerSec;
    public ushort nBlockAlign;
    public ushort wBitsPerSample;
    public ushort cbSize;
}

public static class WasapiPlayer {
    const int CLSCTX_ALL = 23;
    const int AUDCLNT_SHAREMODE_SHARED = 0;
    const int AUDCLNT_STREAMFLAGS_NONE = 0;
    static readonly Guid KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = new Guid("00000003-0000-0010-8000-00AA00389B71");

    static bool IsFloatFormat(IntPtr pFormat, WAVEFORMATEX fmt) {
        if (fmt.wFormatTag == 3) return true; // WAVE_FORMAT_IEEE_FLOAT
        if (fmt.wFormatTag == 0xFFFE) { // WAVE_FORMAT_EXTENSIBLE, SubFormat at offset 24
            try {
                Guid sub = (Guid)Marshal.PtrToStructure(IntPtr.Add(pFormat, 24), typeof(Guid));
                return sub == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
            } catch { return false; }
        }
        return false; // PCM int
    }

    static byte[] Resample(byte[] src, int srcDataOffset, int srcDataSize, WAVEFORMATEX srcFmt, WAVEFORMATEX dstFmt, bool dstFloat) {
        int srcFrameBytes = srcFmt.nBlockAlign;
        int dstFrameBytes = dstFmt.nBlockAlign;
        int srcBytesPerSample = srcFmt.wBitsPerSample / 8;
        int srcFrames = srcDataSize / srcFrameBytes;
        double ratio = (double)dstFmt.nSamplesPerSec / srcFmt.nSamplesPerSec;
        int dstFrames = (int)Math.Ceiling(srcFrames * ratio);
        byte[] outData = new byte[dstFrames * dstFrameBytes];

        for (int i = 0; i < dstFrames; i++) {
            double srcPos = i / ratio;
            int idx0 = (int)Math.Floor(srcPos);
            int idx1 = Math.Min(idx0 + 1, srcFrames - 1);
            double frac = srcPos - idx0;

            for (int dch = 0; dch < dstFmt.nChannels; dch++) {
                int sch = (srcFmt.nChannels == 1) ? 0 : Math.Min(dch, srcFmt.nChannels - 1);
                short s0 = BitConverter.ToInt16(src, srcDataOffset + idx0 * srcFrameBytes + sch * srcBytesPerSample);
                short s1 = BitConverter.ToInt16(src, srcDataOffset + idx1 * srcFrameBytes + sch * srcBytesPerSample);
                double v = (s0 + (s1 - s0) * frac) / 32768.0;

                if (dstFloat) {
                    float f = (float)v;
                    byte[] fb = BitConverter.GetBytes(f);
                    Buffer.BlockCopy(fb, 0, outData, i * dstFrameBytes + dch * 4, 4);
                } else {
                    short s = (short)Math.Max(-32768, Math.Min(32767, v * 32767.0));
                    byte[] sb = BitConverter.GetBytes(s);
                    Buffer.BlockCopy(sb, 0, outData, i * dstFrameBytes + dch * 2, 2);
                }
            }
        }
        return outData;
    }

    public static void Play(string path) {
        byte[] file = File.ReadAllBytes(path);
        int fmtOffset = -1, fmtSize = 0;
        int dataOffset = -1, dataSize = 0;
        int pos = 12;
        while (pos + 8 <= file.Length) {
            string id = System.Text.Encoding.ASCII.GetString(file, pos, 4);
            int size = BitConverter.ToInt32(file, pos + 4);
            if (id == "fmt ") { fmtOffset = pos + 8; fmtSize = size; }
            else if (id == "data") { dataOffset = pos + 8; dataSize = size; }
            pos += 8 + size + (size & 1);
            if (fmtOffset >= 0 && dataOffset >= 0) break;
        }
        if (fmtOffset < 0 || dataOffset < 0 || dataSize <= 0)
            throw new InvalidOperationException("Invalid WAV file");

        WAVEFORMATEX srcFmt = new WAVEFORMATEX();
        srcFmt.wFormatTag = BitConverter.ToUInt16(file, fmtOffset);
        srcFmt.nChannels = BitConverter.ToUInt16(file, fmtOffset + 2);
        srcFmt.nSamplesPerSec = BitConverter.ToUInt32(file, fmtOffset + 4);
        srcFmt.nAvgBytesPerSec = BitConverter.ToUInt32(file, fmtOffset + 8);
        srcFmt.nBlockAlign = BitConverter.ToUInt16(file, fmtOffset + 12);
        srcFmt.wBitsPerSample = BitConverter.ToUInt16(file, fmtOffset + 14);
        srcFmt.cbSize = 0;

        var enumerator = new MMDeviceEnumeratorComObject();
        var imm = (IMMDeviceEnumerator)enumerator;
        IMMDevice device;
        int hr = imm.GetDefaultAudioEndpoint(0, 0, out device);
        if (hr != 0) throw new InvalidOperationException("GetDefaultAudioEndpoint failed");

        Guid iidAudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        object audioClientObj;
        hr = device.Activate(ref iidAudioClient, CLSCTX_ALL, IntPtr.Zero, out audioClientObj);
        if (hr != 0) throw new InvalidOperationException("Activate failed");
        var audioClient = (IAudioClient)audioClientObj;

        IntPtr pMix;
        hr = audioClient.GetMixFormat(out pMix);
        if (hr != 0) throw new InvalidOperationException("GetMixFormat failed");
        WAVEFORMATEX dstFmt = (WAVEFORMATEX)Marshal.PtrToStructure(pMix, typeof(WAVEFORMATEX));
        bool dstFloat = IsFloatFormat(pMix, dstFmt);

        hr = audioClient.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_NONE, 10000000, 0, pMix, IntPtr.Zero);
        Marshal.FreeCoTaskMem(pMix);
        if (hr != 0) throw new InvalidOperationException("Initialize failed");

        Guid iidRenderClient = new Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2");
        object renderClientObj;
        hr = audioClient.GetService(ref iidRenderClient, out renderClientObj);
        if (hr != 0) throw new InvalidOperationException("GetService failed");
        var renderClient = (IAudioRenderClient)renderClientObj;

        int bufferSize;
        audioClient.GetBufferSize(out bufferSize);

        byte[] playData = Resample(file, dataOffset, dataSize, srcFmt, dstFmt, dstFloat);
        int frameBytes = dstFmt.nBlockAlign;
        // Append trailing silence so the short sound keeps the audio stream
        // alive long enough for Bluetooth A2DP to establish its link.
        int silenceFrames = (int)(dstFmt.nSamplesPerSec * 1.5);
        byte[] fullData = new byte[playData.Length + silenceFrames * frameBytes];
        Buffer.BlockCopy(playData, 0, fullData, 0, playData.Length);
        int totalFrames = fullData.Length / frameBytes;
        int framesWritten = 0;

        audioClient.Start();

        try {
            while (framesWritten < totalFrames) {
                int padding;
                audioClient.GetCurrentPadding(out padding);
                int available = bufferSize - padding;
                int toWrite = Math.Min(available, totalFrames - framesWritten);
                if (toWrite <= 0) { Thread.Sleep(5); continue; }
                IntPtr buf;
                renderClient.GetBuffer(toWrite, out buf);
                Marshal.Copy(fullData, framesWritten * frameBytes, buf, toWrite * frameBytes);
                renderClient.ReleaseBuffer(toWrite, 0);
                framesWritten += toWrite;
            }
            int guard = 0;
            while (guard < 4000) {
                int padding;
                audioClient.GetCurrentPadding(out padding);
                if (padding == 0) break;
                Thread.Sleep(5);
                guard++;
            }
        } finally {
            audioClient.Stop();
        }
    }
}
'@

Add-Type -TypeDefinition $cs

[WasapiPlayer]::Play($Path)
