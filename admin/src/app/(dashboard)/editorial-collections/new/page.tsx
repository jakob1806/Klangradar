import { createCollection } from "../actions";
import { CollectionForm } from "../collection-form";

export default function NewEditorialCollectionPage() {
  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Neue Sammlung</h1>
      <div className="mt-6">
        <CollectionForm action={createCollection} />
      </div>
    </div>
  );
}
