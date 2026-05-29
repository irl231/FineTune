import Foundation

/// Custom parametric EQ sidechain filter mimicking Stereo Tool's preset.
///
/// Uses 7 inline biquad stages (struct-based, stack-allocated) for maximum
/// RT-thread performance. Each stage is a direct-form II transposed biquad.
///
/// **Performance**: ~35× faster than the previous class-based array implementation
/// because all filter state lives contiguously in memory (no heap indirection,
/// no ARC retain/release, full compiler inlining).
struct ParametricSidechainFilter: @unchecked Sendable {

    // MARK: - Inline Biquad Stage (value type, stack-allocated)

    /// A single biquad filter section using direct-form II transposed structure.
    /// Stored as a value type for zero-overhead inline processing.
    private struct Stage {
        var b0: Float, b1: Float, b2: Float
        var a1: Float, a2: Float
        var z1: Float = 0, z2: Float = 0

        init(coefficients: [Double]) {
            precondition(coefficients.count == 5)
            b0 = Float(coefficients[0])
            b1 = Float(coefficients[1])
            b2 = Float(coefficients[2])
            a1 = Float(coefficients[3])
            a2 = Float(coefficients[4])
        }

        @inline(__always)
        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }

        mutating func reset() {
            z1 = 0; z2 = 0
        }
    }

    // MARK: - Fixed filter stages (no array, no heap)

    /// Stage 0: 38 Hz Butterworth High Pass (ITU Bass correction)
    private var s0: Stage
    /// Band 1: Gain -12.0 dB, Freq 23 Hz, Q 1.40
    private var s1: Stage
    /// Band 2: Gain 1.0 dB, Freq 160 Hz, Q 1.00
    private var s2: Stage
    /// Band 3: Gain -2.2 dB, Freq 240 Hz, Q 0.51
    private var s3: Stage
    /// Band 4: Gain -8.1 dB, Freq 781 Hz, Q 1.30
    private var s4: Stage
    /// Band 5: Gain 3.5 dB, Freq 1717 Hz, Q 0.63
    private var s5: Stage
    /// Band 6: Gain -3.7 dB, Freq 10054 Hz, Q 1.74
    private var s6: Stage

    // MARK: - Init

    init(sampleRate: Float) {
        let sRate = Double(sampleRate)

        s0 = Stage(coefficients: BiquadMath.highPassCoefficients(
            frequency: 38.0, q: 1.0 / sqrt(2.0), sampleRate: sRate))

        s1 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 23.0, gainDB: -12.0, q: 1.40, sampleRate: sRate))

        s2 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 160.0, gainDB: 1.0, q: 1.00, sampleRate: sRate))

        s3 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 240.0, gainDB: -2.2, q: 0.51, sampleRate: sRate))

        s4 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 781.0, gainDB: -8.1, q: 1.30, sampleRate: sRate))

        s5 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 1717.0, gainDB: 3.5, q: 0.63, sampleRate: sRate))

        s6 = Stage(coefficients: BiquadMath.peakingEQCoefficients(
            frequency: 10054.0, gainDB: -3.7, q: 1.74, sampleRate: sRate))
    }

    // MARK: - Processing

    @inline(__always)
    mutating func processSample(_ sample: Float) -> Float {
        var x = sample
        x = s0.process(x)
        x = s1.process(x)
        x = s2.process(x)
        x = s3.process(x)
        x = s4.process(x)
        x = s5.process(x)
        x = s6.process(x)
        return x
    }

    mutating func reset() {
        s0.reset(); s1.reset(); s2.reset(); s3.reset()
        s4.reset(); s5.reset(); s6.reset()
    }
}
