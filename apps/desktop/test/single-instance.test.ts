import { expect,test,vi } from "vitest";
import { claimSingleInstance } from "../src/main/single-instance";
test("secondary launch opens the one primary native settings process",()=>{
  let listener:(()=>void)|undefined;const show=vi.fn();
  const app={requestSingleInstanceLock:()=>true,quit:vi.fn(),on:(_name:string,fn:()=>void)=>{listener=fn;}};
  expect(claimSingleInstance(app,show)).toBe(true);listener?.();expect(show).toHaveBeenCalledOnce();
});
test("a second service owner quits before initializing",()=>{
  const app={requestSingleInstanceLock:()=>false,quit:vi.fn(),on:vi.fn()};const show=vi.fn();
  expect(claimSingleInstance(app,show)).toBe(false);expect(app.quit).toHaveBeenCalledOnce();expect(show).not.toHaveBeenCalled();
});
