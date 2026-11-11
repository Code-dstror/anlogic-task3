"""Exercise configured MCP servers over stdio, without a Codex restart."""
import argparse
import asyncio
import json
import os
import tomllib
from pathlib import Path

from mcp import Client, StdioServerParameters


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("server")
    parser.add_argument("--calls", type=Path, help="JSON list of {name,arguments}")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    config = tomllib.loads((root / ".codex/config.toml").read_text(encoding="utf-8-sig"))
    server = config["mcp_servers"][args.server]
    env = dict(os.environ)
    env.update(server.get("env", {}))
    params = StdioServerParameters(command=server["command"], args=server.get("args", []), env=env)
    result = {"server": args.server, "status": "STARTED", "calls": []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        async with Client(params, read_timeout_seconds=240) as session:
            result["server_info"] = session.server_info.model_dump(mode="json") if session.server_info else None
            listing = await session.list_tools()
            result["tools"] = [t.model_dump(mode="json") for t in listing.tools]
            save()
            print("Tools:", ", ".join(t.name for t in listing.tools), flush=True)
            calls = json.loads(args.calls.read_text(encoding="utf-8-sig")) if args.calls else []
            for call in calls:
                print("Calling", call["name"], flush=True)
                output = await session.call_tool(call["name"], call.get("arguments", {}))
                result["calls"].append({**call, "result": output.model_dump(mode="json")})
                save()
                if output.is_error:
                    raise RuntimeError(f"Tool returned error: {call['name']}")
                expected = call.get("expect_text")
                if expected and expected not in json.dumps(output.model_dump(mode="json"), ensure_ascii=False):
                    raise RuntimeError(f"Missing success marker for {call['name']}: {expected}")
            result["status"] = "PASS"
            save()
    except BaseException as exc:
        result.update(status="FAIL", error=str(exc))
        save()
        raise


if __name__ == "__main__":
    asyncio.run(main())
