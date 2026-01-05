import CoreLocation
import PrayerKit
import SwiftUI

struct PrayerSectionView: View {
    let coordinate: CLLocationCoordinate2D
    let fontScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prayer")
                .font(.system(size: 12 * fontScale))
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                let next = PrayerKit.nextPrayer(
                    now: context.date,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    timeZone: .current
                )

                if let next {
                    HStack(spacing: 6) {
                        Text("\(next.prayer.displayName):")
                            .font(.system(size: 13 * fontScale, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(next.time, style: .time)
                            .font(.system(size: 13 * fontScale))
                            .foregroundStyle(.white.opacity(0.95))

                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Prayer time unavailable.")
                        .font(.system(size: 13 * fontScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .padding(.horizontal, StickyNoteLayout.contentPadding)
    }
}
