import { describe, expect, test } from "vitest";
import { stylePreferenceSchema, writingPreferencesSchema, personalizationEditSchema, preferenceExtractionRequestSchema, preferenceExtractionResponseSchema } from "../src/learning";
const id = "00000000-0000-4000-8000-000000000001";
const preference = { id, dimension: "concision", value: "concise", appId: "com.apple.Notes", origin: "learned" };
const observation = { id, sessionId: id, appId: "com.apple.Notes", before: "A rather long update", after: "An update" };
describe("bounded learning contract", () => {
  test("accepts bounded style traits and scopes learned preferences to an app", () => {
    expect(stylePreferenceSchema.safeParse(preference).success).toBe(true);
    expect(stylePreferenceSchema.safeParse({ ...preference, appId: null }).success).toBe(false);
    expect(stylePreferenceSchema.safeParse({ ...preference, origin: "explicit", appId: null }).success).toBe(true);
    expect(stylePreferenceSchema.safeParse({ ...preference, value: "formal" }).success).toBe(false);
    expect(stylePreferenceSchema.safeParse({ ...preference, language: "Spanish" }).success).toBe(false);
  });
  test("rejects duplicate ids and oversized active preferences", () => {
    expect(writingPreferencesSchema.safeParse([preference, preference]).success).toBe(false);
    expect(writingPreferencesSchema.safeParse(Array.from({length:25}, (_, i) => ({...preference,id:`00000000-0000-4000-8000-${String(i).padStart(12,"0")}`}))).success).toBe(false);
  });
  test("allows signed-out basic settings only without personalization mutations", () => {
    const edit = { accountSubject: "", enabled: false, edits: [], forgetIds: [], reset: false };
    expect(personalizationEditSchema.safeParse(edit).success).toBe(true);
    for (const change of [{enabled:true}, {reset:true}, {edits:[preference]}, {forgetIds:[id]}]) expect(personalizationEditSchema.safeParse({...edit,...change}).success).toBe(false);
  });
  test.each([{before:" "}, {after:"A rather long update"}, {before:"a".repeat(2001)}])("rejects invalid observed correction %#", change => {
    expect(preferenceExtractionRequestSchema.safeParse({observations:[{...observation,...change}]}).success).toBe(false);
  });
  test("bounds and deduplicates observations", () => {
    expect(preferenceExtractionRequestSchema.safeParse({observations:[observation]}).success).toBe(true);
    expect(preferenceExtractionRequestSchema.safeParse({observations:[observation,observation]}).success).toBe(false);
    expect(preferenceExtractionRequestSchema.safeParse({observations:[]}).success).toBe(false);
  });
  test("allows zero evidence and at most one value per observation dimension", () => {
    const evidence = {observationId:id,dimension:"concision",value:"concise"};
    expect(preferenceExtractionResponseSchema.safeParse({evidence:[]}).success).toBe(true);
    expect(preferenceExtractionResponseSchema.safeParse({evidence:[evidence]}).success).toBe(true);
    expect(preferenceExtractionResponseSchema.safeParse({evidence:[evidence,{...evidence,value:"detailed"}]}).success).toBe(false);
    expect(preferenceExtractionResponseSchema.safeParse({evidence:[{...evidence,fact:"a customer name"}]}).success).toBe(false);
  });
});
