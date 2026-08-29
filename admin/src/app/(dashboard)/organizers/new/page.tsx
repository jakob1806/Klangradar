import { OrganizerForm } from "../organizer-form";
import { createOrganizer } from "../actions";
export default function NewOrganizerPage(){return <div className="p-8"><h1 className="text-xl font-semibold tracking-tight">Veranstalter anlegen</h1><div className="mt-6"><OrganizerForm action={createOrganizer}/></div></div>}
