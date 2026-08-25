import { createVenue, getCityOptions } from "../actions";
import { VenueForm } from "../venue-form";

export default async function NewVenuePage() {
  const cities = await getCityOptions();
  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Neue Venue</h1>
      <div className="mt-6">
        <VenueForm action={createVenue} cities={cities} />
      </div>
    </div>
  );
}
