import AppKit

/// Each catalogue visit may temporarily replace the live voyage (a workshop trial)
/// or open another replay. Keep the activity that actually opened that catalogue.
struct CatalogReturn {
    struct Film {
        let level: MistLevel
        let route: [MistCommand]
        let step: Int
    }
    struct Studio {
        let active: MistWorkshopChart?
        let selection: String?
        let authoring: Bool
        let fromAfterpost: Bool
        let page: Int
    }
    let desk: Desk
    let voyage: MistVoyage
    let wire: MistChallenge?
    let selectedWire: MistChallenge?
    let letterReturn: Desk
    let chapter: Int
    let film: Film?
    let studio: Studio?

    @MainActor init(_ view: StationView) {
        desk = view.desk
        voyage = view.voyage
        wire = view.activeWire
        selectedWire = view.selectedWire
        letterReturn = view.letterReturn
        chapter = view.chapter
        if desk == .replay, let trip = view.replayTrip {
            film = Film(level:trip.level,route:view.replayRoute,step:view.replayIndex)
        } else { film = nil }
        if voyage.level.id < 0 || desk == .workshop || desk == .chartCase || desk == .studioReceipt {
            let s = view.studio
            studio = Studio(active:s.active,selection:s.selection,authoring:s.authoring,fromAfterpost:s.fromAfterpost,page:s.page)
        } else { studio = nil }
    }

    @MainActor func restore(_ view: StationView) {
        view.desk = desk
        view.voyage = voyage
        view.activeWire = wire
        view.selectedWire = selectedWire
        view.letterReturn = letterReturn
        view.chapter = chapter
        view.hint = nil
        view.lastEvent = ""
        view.wireNotice = nil
        view.motionAt = nil
        if let saved = studio {
            let s = view.studio
            s.active = saved.active
            s.selection = saved.selection
            s.authoring = saved.authoring
            s.fromAfterpost = saved.fromAfterpost
            s.page = saved.page
            // The author can revise the draft during a detour. Resume its current
            // verified history, so a discarded trial cannot overwrite that edit.
            if desk == .sailing, voyage.level.id < 0, let resumed = s.begin(author:saved.authoring) {
                view.voyage = resumed
            }
        }
        if let film {
            view.openReplay(level:film.level,route:film.route)
            view.seekReplay(film.step)
            view.motionAt = nil
        }
    }
}
