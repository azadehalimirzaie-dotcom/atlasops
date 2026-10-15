from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class NetworkEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    event_id: str = Field(
        min_length=1,
        max_length=128,
        pattern=r"^[A-Za-z0-9._:-]+$",
    )
    device_id: str = Field(min_length=1, max_length=128)
    event_type: str = Field(min_length=1, max_length=64)
    severity: Literal["info", "warning", "critical"]
    timestamp: AwareDatetime
    message: str = Field(min_length=1, max_length=4096)