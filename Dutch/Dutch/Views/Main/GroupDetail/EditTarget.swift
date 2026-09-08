/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData

/// The member being edited, with the avatar the row was already showing so the
/// sheet opens on it rather than re-deriving one.
///
/// Keyed on the object id for the same reason `FormTarget` is: `Person.id` is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` one would simply
/// never present.
struct EditTarget: Identifiable {
    let member: Person
    let avatar: PersonAvatar

    var id: NSManagedObjectID { member.objectID }
}
