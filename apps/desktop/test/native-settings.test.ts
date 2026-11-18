import { expect, test } from "vitest";
import { parseNativeRequest } from "../src/main/native-settings-protocol";

test("native IPC only accepts named intents and bounded finite preferences", () => {
  expect(parseNativeRequest(JSON.stringify({id:"a",action:"pause",payload:"30m"}))).toMatchObject({action:"pause",payload:"30m"});
  expect(parseNativeRequest(JSON.stringify({id:"w",action:"saveWriting",payload:{automaticSuggestions:false,timing:"quick",visibility:"clear",personalization:{accountSubject:"",enabled:false,edits:[],forgetIds:[],reset:false}}}))).toMatchObject({action:"saveWriting",payload:{automaticSuggestions:false,timing:"quick",visibility:"clear",personalization:{accountSubject:"",enabled:false,edits:[],forgetIds:[],reset:false}}});
  for (const data of [
    {id:"a",action:"pause",payload:null},
    {id:"a",action:"setEnabled",payload:false},
    {id:"a",action:"openExternal",payload:"file:///private/secret"},
    {id:"a",action:"saveWriting",payload:{automaticSuggestions:true,timing:"zero",visibility:"clear"}},
    {id:"a",action:"saveWriting",payload:{automaticSuggestions:true,timing:"quick"}},
    {id:"a",action:"saveWriting",payload:{automaticSuggestions:true,timing:"quick",visibility:"clear",apps:{}}},
    {id:"a",action:"libraryImport",payload:{title:"x",kind:"style",scope:{appIds:[],anchor:""},expiresAt:null,path:"/private/data"}},
  ]) expect(() => parseNativeRequest(JSON.stringify(data))).toThrow();
});
