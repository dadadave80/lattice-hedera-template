import type { NextPage } from "next";
import { FacetTable } from "~~/components/diamond/FacetTable";
import { UpgradeCard } from "~~/components/diamond/UpgradeCard";
import { getMetadata } from "~~/utils/scaffold-hbar/getMetadata";

export const metadata = getMetadata({
  title: "Diamond",
  description: "The facets behind this project's diamond, and a tool to cut a new one in",
});

const Diamond: NextPage = () => {
  return (
    <div className="w-full max-w-4xl mx-auto px-5 py-10 flex flex-col gap-6">
      <div>
        <h1 className="text-3xl font-bold m-0">Diamond</h1>
        <p className="text-base-content/70 m-0 mt-2">
          One address, many facets. The table is read live from the diamond&apos;s loupe, so it changes the moment a cut
          lands.
        </p>
      </div>
      <FacetTable />
      <UpgradeCard />
    </div>
  );
};

export default Diamond;
