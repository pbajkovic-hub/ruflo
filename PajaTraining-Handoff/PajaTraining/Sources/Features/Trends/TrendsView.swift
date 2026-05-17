import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: TrendsViewModel

    init() {
        _vm = StateObject(wrappedValue: TrendsViewModel(db: DatabaseStore(), userId: ""))
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.isLoading {
                    ProgressView()
                } else {
                    rangePickerSection
                    recoverySection
                    volumeSection
                    bodyCompSection
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await vm.load() }
    }

    private var rangePickerSection: some View {
        Section {
            Picker("Range", selection: $vm.rangeDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.rangeDays) { _, _ in Task { await vm.load() } }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var recoverySection: some View {
        Section("Recovery") {
            if vm.recoveryPoints.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                Chart(vm.recoveryPoints) { pt in
                    LineMark(x: .value("Date", pt.date),
                             y: .value("Recovery", pt.pct))
                        .foregroundStyle(Color.recovery(pt.state))
                    PointMark(x: .value("Date", pt.date),
                              y: .value("Recovery", pt.pct))
                        .foregroundStyle(Color.recovery(pt.state))
                }
                .frame(height: 160)
                .chartYScale(domain: 0...100)
            }
        }
    }

    private var volumeSection: some View {
        Section("Weekly Volume") {
            if vm.volumePoints.isEmpty {
                Text("Log sessions to see volume trends.").foregroundStyle(.secondary)
            } else {
                Chart(vm.volumePoints) { pt in
                    BarMark(x: .value("Week", pt.weekStart),
                            y: .value("Volume (kg)", pt.totalKg))
                        .foregroundStyle(Color.pajaGreen)
                }
                .frame(height: 140)
            }
        }
    }

    private var bodyCompSection: some View {
        Section("Body Composition") {
            if vm.bodyCompPoints.isEmpty {
                Text("No body composition data yet.\nConnect Apple Health or add weekly entries.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Chart(vm.bodyCompPoints) { pt in
                    if let w = pt.weightKg {
                        LineMark(x: .value("Date", pt.date),
                                 y: .value("Weight (kg)", w))
                            .foregroundStyle(Color.pajaGreen)
                    }
                }
                .frame(height: 120)
            }
        }
    }
}
