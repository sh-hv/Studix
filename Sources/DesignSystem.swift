import SwiftUI

// Shared visual language for every screen. Keep components small so new features
// can reuse the same spacing, surfaces, and typography without coupling to views.
struct StudixSurface: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }
}

extension View {
    func studixSurface(radius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(StudixSurface(radius: radius, padding: padding))
    }
}

struct DashboardHero: View {
    let subjectCount: Int
    let itemCount: Int
    let taskCount: Int

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return Lang.tr("صباح الخير") }
        if hour < 18 { return Lang.tr("مساء النشاط") }
        return Lang.tr("مساء الخير")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("خلّ دراستك أكثر تنظيمًا")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Lang.locale)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 0) {
                metric(value: subjectCount, title: "المواد", icon: "books.vertical.fill")
                Spacer(minLength: 8)
                metric(value: itemCount, title: "ملفاتك", icon: "folder.fill")
                Spacer(minLength: 8)
                metric(value: taskCount, title: "المهام", icon: "checkmark.circle.fill")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.28, blue: 0.78), Color(red: 0.34, green: 0.38, blue: 0.94), Color(red: 0.22, green: 0.57, blue: 0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 150, height: 150)
                .offset(x: 35, y: 55)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .shadow(color: Theme.accent.opacity(0.22), radius: 18, y: 9)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func metric(value: Int, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
            Text(value.formatted(.number.locale(Lang.locale)))
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
